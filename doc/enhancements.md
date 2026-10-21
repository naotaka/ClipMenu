# ClipMenu — Architecture Enhancement Proposals

This document proposes concrete modernisation improvements for ClipMenu. Each enhancement describes the current problem, the modern alternative, migration strategy, and trade-offs. Proposals are ordered from highest to lowest impact.

All proposals target **macOS 13 Ventura+** as the minimum deployment target and **Swift 5.9+** as the implementation language, unless noted otherwise.

---

## 1. Clipboard Monitoring — Replace Polling with Change Notification

### Current Design

`ClipsController` uses a repeating `NSTimer` (default 0.75 s, max 1.0 s) that reads `[NSPasteboard generalPasteboard].changeCount` on every tick. This wakes the process ~80 times per minute even when the clipboard is idle.

### Problem

- Wastes CPU and battery on idle systems.
- Introduces latency: a copy made 1 ms after a tick won't be captured for up to 750 ms.
- The hard cap of 1.0 s is an arbitrary workaround, not a design principle.

### Proposed Solution

Use `NSPasteboard`'s KVO support via `addObserver(_:forKeyPath:options:context:)` on the `changeCount` property. On macOS 10.8+ this fires synchronously when the pasteboard changes, with zero polling overhead.

```swift
// ClipboardMonitor.swift
import AppKit
import Combine

final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var observation: NSKeyValueObservation?
    let clipChanged = PassthroughSubject<NSPasteboard, Never>()

    func start() {
        observation = pasteboard.observe(\.changeCount, options: [.new]) { [weak self] pb, _ in
            self?.clipChanged.send(pb)
        }
    }

    func stop() {
        observation = nil
    }
}
```

The `ClipboardMonitor` publishes on `clipChanged`. `ClipsService` (replacement for `ClipsController`) subscribes and processes the new content.

### Trade-offs

- `NSPasteboard.changeCount` KVO is documented as reliable on macOS 10.8+, which is well below the new minimum target.
- Eliminates timer drift: two rapid copies in quick succession won't be coalesced by a polling window.
- If Apple ever restricts KVO on `NSPasteboard` (not currently the case), the fallback is a 250 ms timer — still faster than the current default and only needed as a safety net.

---

## 2. Persistence — Replace NSKeyedArchiver + Core Data with SwiftData

### Current Design

| Data | Mechanism | File |
|---|---|---|
| Clip history | `NSKeyedArchiver` | `clips.data` |
| Action nodes | `NSPropertyListSerialization` | `actions.plist` |
| Snippets | Core Data XML store | `Snippets.xml` |

Three separate persistence stacks, each with their own save/load paths, error handling, and migration stories.

### Problems

- `clips.data` is a monolithic binary blob; a single corrupt byte loses the entire history.
- Core Data requires a heavyweight coordinator/context/store stack for a simple two-entity model.
- No incremental writes: every save rewrites the whole clip array.
- NSKeyedArchiver format changes require manual backward-compat decoding (already present in `Clip.initWithCoder:`).

### Proposed Solution

Adopt **SwiftData** (macOS 14+) as a single persistence layer for all three data sets.

#### Model

```swift
import SwiftData

@Model
final class ClipEntry {
    var createdAt: Date
    var lastUsedAt: Date
    var types: [String]          // pasteboard type UTI strings
    var stringValue: String?
    var rtfData: Data?
    var pdfData: Data?
    var filenames: [String]?
    var urlStrings: [String]?
    var imageData: Data?         // TIFF representation

    init(createdAt: Date = .now) {
        self.createdAt = createdAt
        self.lastUsedAt = createdAt
        self.types = []
    }
}

@Model
final class SnippetFolder {
    var title: String
    var isEnabled: Bool
    var sortIndex: Int
    @Relationship(deleteRule: .cascade) var snippets: [Snippet] = []
}

@Model
final class Snippet {
    var title: String
    var content: String
    var isEnabled: Bool
    var sortIndex: Int
    var folder: SnippetFolder?
}

@Model
final class ActionNode {
    var title: String
    var isLeaf: Bool
    var sortIndex: Int
    var actionType: String?      // "builtin" | "javaScript"
    var actionName: String?
    var scriptPath: String?
    @Relationship(deleteRule: .cascade) var children: [ActionNode] = []
}
```

#### Container Setup

```swift
let schema = Schema([ClipEntry.self, SnippetFolder.self, Snippet.self, ActionNode.self])
let config = ModelConfiguration("ClipMenu", schema: schema)
let container = try ModelContainer(for: schema, configurations: config)
```

SwiftData automatically places the store at `~/Library/Application Support/ClipMenu/default.store` (SQLite).

#### Migration from Legacy Formats

Write a one-time migration routine that runs on first launch after the update:

1. Check for `clips.data`; if present, unarchive via `NSKeyedUnarchiver`, insert each clip into the SwiftData context, delete the file.
2. Check for `Snippets.xml`; if present, load the Core Data store using the old coordinator, read all objects, insert into SwiftData, delete the file.
3. Check for `actions.plist`; parse it, insert `ActionNode` objects, delete the file.

Mark migration complete in `UserDefaults` with a version key so it never runs twice.

### Benefits

- Single SQLite file; SQLite is append-friendly and recovers from partial writes.
- Free incremental writes — only changed rows are written.
- Built-in versioned schema migration via `MigrationPlan`.
- `@Query` descriptor in SwiftUI views replaces `sortedClips` computed property.
- Automatic background context for saves; no manual thread management.

---

## 3. Concurrency — Replace NSThread/NSOperationQueue with Swift Concurrency

### Current Design

- Startup uses `NSOperationQueue` to run clip load, action load, and hotkey registration concurrently.
- Autosave detaches a raw `NSThread` via `NSThread.detachNewThreadSelector:`.
- The rest of the app is single-threaded on the main thread with no formal actor boundary.

### Proposed Solution

Replace with `async/await` and `Actor`s.

```swift
// ClipsService.swift
actor ClipsService {
    private var clips: [ClipEntry] = []
    private let modelContext: ModelContext

    func loadClips() async throws {
        let descriptor = FetchDescriptor<ClipEntry>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)])
        clips = try modelContext.fetch(descriptor)
    }

    func addClip(_ entry: ClipEntry) async {
        modelContext.insert(entry)
        try? modelContext.save()
        await MainActor.run { NotificationCenter.default.post(name: .clipsDidChange, object: nil) }
    }
}
```

Startup becomes a single `async` block:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    Task {
        async let clips: () = clipsService.loadClips()
        async let actions: () = actionService.loadActions()
        async let hotkeys: () = hotkeyService.register()
        try await (clips, actions, hotkeys)
    }
}
```

Autosave uses `Task.sleep` instead of `NSTimer`:

```swift
func startAutosave(interval: Duration) {
    Task.detached(priority: .background) { [weak self] in
        while true {
            try await Task.sleep(for: interval)
            await self?.saveIfNeeded()
        }
    }
}
```

---

## 4. Global Hotkeys — Replace PTHotKeys (Carbon) with ShortcutRecorder or EventKit

### Current Design

PTHotKeys registers hotkeys via legacy Carbon `RegisterEventHotKey` APIs. These APIs are available but deprecated and rely on the Carbon event loop, which is not guaranteed in future OS versions.

### Problems

- Carbon dependency (`Carbon/Carbon.h`).
- `PTKeyCombo` serialises as raw key-code + modifier integer, which is keyboard-layout-dependent.
- No support for non-ASCII key descriptions in modifier display.

### Proposed Solution

Use `MASShortcut` or `KeyboardShortcuts` (by Sindre Sorhus), both of which use CGEventTap internally:

```swift
// Using the KeyboardShortcuts package
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openClipMenu = Self("openClipMenu", default: .init(.v, modifiers: [.command, .shift]))
    static let openHistory  = Self("openHistory",  default: .init(.v, modifiers: [.command, .control]))
    static let openSnippets = Self("openSnippets", default: .init(.b, modifiers: [.command, .shift]))
}

// Registration (replaces _registerHotKeys)
KeyboardShortcuts.onKeyUp(for: .openClipMenu) { [weak self] in self?.openClipMenu() }
KeyboardShortcuts.onKeyUp(for: .openHistory)  { [weak self] in self?.openHistory() }
KeyboardShortcuts.onKeyUp(for: .openSnippets) { [weak self] in self?.openSnippets() }
```

Preferences UI uses `KeyboardShortcuts.Recorder` (SwiftUI view) instead of ShortcutRecorder XIB controls.

Hotkey configurations are stored automatically in `UserDefaults` under the shortcut name, in a layout-independent format.

---

## 5. UI — Replace NSMenu/XIB with SwiftUI MenuBarExtra

### Current Design

`MenuController` manually builds `NSMenu` and all `NSMenuItem` objects in code, including custom attributed strings, thumbnails, icons, and submenus. XIB files define the preferences window.

### Proposed Solution

macOS 13 introduced `MenuBarExtra` — a SwiftUI scene that renders a menu or popover directly in the menu bar.

```swift
@main
struct ClipMenuApp: App {
    var body: some Scene {
        MenuBarExtra("ClipMenu", systemImage: "doc.on.clipboard") {
            ClipMenuView()
        }
        .menuBarExtraStyle(.menu)   // or .window for a popover
    }
}
```

The content view uses `@Query` to fetch clips directly from SwiftData with live updates:

```swift
struct ClipMenuView: View {
    @Query(sort: \ClipEntry.lastUsedAt, order: .reverse) var clips: [ClipEntry]
    @Query var snippetFolders: [SnippetFolder]

    var body: some View {
        ForEach(clips) { clip in
            ClipMenuItem(clip: clip)
        }
        Divider()
        SnippetsSection(folders: snippetFolders)
        Divider()
        ControlsSection()
    }
}
```

The preferences window becomes a `Settings` scene:

```swift
Settings {
    PreferencesView()
        .frame(width: 500)
}
```

### Trade-offs

- `MenuBarExtra` with `.menuBarExtraStyle(.menu)` renders identically to `NSMenu` in appearance.
- Custom menu item views (thumbnails, icons) are fully supported via `Label` and custom `View`s inside the menu.
- Keyboard shortcuts for menu items use SwiftUI's `.keyboardShortcut(_:modifiers:)` modifier.
- XIB files are eliminated entirely.

---

## 6. JavaScript Engine — Replace WebView with JavaScriptCore

### Current Design

`ActionController` creates a hidden `WebView`, loads an empty HTML string, and uses `WebScriptObject` to evaluate JavaScript actions. `WebView` is deprecated as of macOS 10.14.

### Problems

- `WebView` (WebKit legacy) is deprecated and may be removed.
- Spinning up a `WebView` for script execution is heavyweight.
- `WebScriptObject` bridge is fragile and undocumented in modern SDKs.
- External resource access must be manually blocked via the policy delegate.

### Proposed Solution

Use `JavaScriptCore.framework` directly:

```swift
import JavaScriptCore

final class ScriptEngine {
    private let context = JSContext()!

    init() {
        // Inject ClipMenu namespace
        let clipMenuObj = JSValue(newObjectIn: context)
        context["ClipMenu"] = clipMenuObj

        // ClipMenu.require(path) — load a library script
        let require: @convention(block) (String) -> Void = { [weak self] path in
            guard let source = try? String(contentsOfFile: path) else { return }
            self?.context.evaluateScript(source)
        }
        clipMenuObj?.setObject(require, forKeyedSubscript: "require" as NSString)

        // Error handler
        context.exceptionHandler = { _, exception in
            print("JS error: \(exception?.toString() ?? "unknown")")
        }
    }

    func run(script: String, clipText: String, clip: ScriptableClip) -> String? {
        context["clipText"] = clipText
        context["clip"] = clip
        let wrapped = "function __wrapper(clipText, clip) { \(script) }"
        context.evaluateScript(wrapped)
        let result = context.evaluateScript("__wrapper(clipText, clip)")
        guard let str = result?.toString(), result?.isUndefined == false else { return nil }
        return str
    }
}
```

`ScriptableClip` exposes its API via `@objc` and `JSExport`:

```swift
@objc protocol ScriptableClipExport: JSExport {
    func setStringAttributes(_ attrs: [String: Any])
    func addStringAttributes(_ attrs: [String: Any])
    var text: String? { get }
}
```

### Benefits

- No hidden web view, no HTML loading, no deprecated APIs.
- `JSContext` is lightweight and can be created per invocation or pooled.
- Direct Swift bridging via `JSExport` is type-safe and documented.
- No network policy delegate needed: `JSContext` has no network access by default.

---

## 7. Application Exclusion — Replace ProcessSerialNumber with Modern Process APIs

### Current Design

`ClipsController._frontProcessIsInExcludeList` calls `GetFrontProcess(&psn)` and `ProcessInformationCopyDictionary` — both Carbon APIs deprecated in macOS 10.9.

### Proposed Solution

Use `NSWorkspace` notifications and `NSRunningApplication`:

```swift
extension NSWorkspace {
    var frontmostBundleIdentifier: String? {
        frontmostApplication?.bundleIdentifier
    }
}

// In ClipboardMonitor, before processing a change:
func shouldRecord() -> Bool {
    guard let frontId = NSWorkspace.shared.frontmostBundleIdentifier else { return true }
    return !excludedBundleIDs.contains(frontId)
}
```

For the exclude-list panel, enumerate running apps:

```swift
let runningApps = NSWorkspace.shared.runningApplications
    .filter { $0.activationPolicy == .regular }
    .map { ExcludeEntry(name: $0.localizedName ?? "", bundleID: $0.bundleIdentifier ?? "") }
```

---

## 8. Login Items — Replace LSSharedFileList with SMAppService

### Current Design

`NMLoginItems` uses `LSSharedFileListCreate`, `LSSharedFileListInsertItemURL`, and `LSSharedFileListItemRemove` — all deprecated in macOS 10.11.

### Proposed Solution

```swift
import ServiceManagement

func setLaunchAtLogin(_ enabled: Bool) throws {
    if enabled {
        try SMAppService.mainApp.register()
    } else {
        try SMAppService.mainApp.unregister()
    }
}

var isRegisteredAsLoginItem: Bool {
    SMAppService.mainApp.status == .enabled
}
```

`SMAppService` requires no special entitlements and works in sandboxed apps. Available on macOS 13+.

---

## 9. Paste Mechanism — Replace CGEvent Synthesis with Accessibility API

### Current Design

`CMUtilities.paste()` posts synthetic `Cmd+V` keyboard events via `CGEventCreateKeyboardEvent` and `CGEventPost`. It must dynamically scan all 128 keycodes to find the `V` key for the current keyboard layout.

### Problems

- Requires Accessibility permission if running unsandboxed; blocked entirely in sandbox.
- The keycode scan runs on first use and caches the result, but is brittle on layout changes.
- No feedback if the target app doesn't support `Cmd+V`.

### Proposed Solution

Use `NSPasteboard` write + a `CGEvent`-based approach but with the `kCGEventSourceStateHIDSystemState` source, which is more reliable:

```swift
func paste() {
    let src = CGEventSource(stateID: .hidSystemState)
    let vKeyCode: CGKeyCode = 9   // 'V' in ANSI; stored as a constant after one-time lookup
    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
    let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
    keyDown?.flags = .maskCommand
    keyUp?.flags   = .maskCommand
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}
```

For a sandboxed alternative, write the content to the pasteboard and ask the user to press `Cmd+V` manually — or use `NSAppleScript` targeting the frontmost app:

```swift
let script = NSAppleScript(source: "tell application \"System Events\" to keystroke \"v\" using command down")
script?.executeAndReturnError(nil)
```

(The AppleScript approach requires Automation permission for the target app.)

---

## 10. Settings — Replace NSUserDefaults Manual Keys with @AppStorage / Property Wrappers

### Current Design

Over 40 preference keys are scattered across multiple files as `#define` string constants. Defaults are registered manually in `+[AppController initialize]` via a large `NSMutableDictionary`. Preference observation is wired by hand with KVO.

### Proposed Solution

Define a typed settings container:

```swift
struct ClipMenuSettings {
    @AppStorage("maxHistorySize")     var maxHistorySize: Int = 20
    @AppStorage("pollingInterval")    var pollingInterval: Double = 0.75
    @AppStorage("reorderOnPaste")     var reorderOnPaste: Bool = true
    @AppStorage("autosaveDelay")      var autosaveDelay: Int = 1800
    @AppStorage("saveOnQuit")         var saveOnQuit: Bool = true
    @AppStorage("showStatusItem")     var showStatusItem: Bool = true
    @AppStorage("enableActions")      var enableActions: Bool = true
    @AppStorage("positionOfSnippets") var positionOfSnippets: SnippetPosition = .belowClips
    // …etc
}
```

SwiftUI views bind directly to these with `@AppStorage` in the view, or observe via `Combine.Publisher`:

```swift
NotificationCenter.default
    .publisher(for: UserDefaults.didChangeNotification)
    .map { _ in UserDefaults.standard.integer(forKey: "maxHistorySize") }
    .removeDuplicates()
    .sink { [weak self] newSize in self?.clipsService.applyMaxSize(newSize) }
    .store(in: &cancellables)
```

Eliminates all manual KVO setup in `ClipsController` and `AppController`.

---

## 11. Bundled Script Actions — Replace File-System Script Discovery with Swift Plugin Protocol

### Current Design

Action scripts are discovered by walking the file system (`script/action/` directories). The tree is rebuilt at startup and saved to `actions.plist`. Users add custom scripts by dropping files into an Application Support directory.

### Problems

- No type safety, no capability declaration per script.
- Discovery is fragile if the directory layout changes.
- No way to validate a script before it appears in the menu.

### Proposed Solution

Define a `ClipMenuAction` protocol that built-in Swift actions can conform to. Retain the JavaScript engine for user scripts but give it a formal registration API:

```swift
protocol ClipMenuAction: Sendable {
    var id: String { get }
    var title: String { get }
    var applicableTypes: [ClipType] { get }
    func perform(on clip: ClipEntry) async throws -> ClipEntry?
}
```

Built-in actions become Swift structs:

```swift
struct PasteAsPlainTextAction: ClipMenuAction {
    let id = "pasteAsPlainText"
    let title = NSLocalizedString("Paste as Plain Text", comment: "")
    let applicableTypes: [ClipType] = [.string]

    func perform(on clip: ClipEntry) async throws -> ClipEntry? {
        guard let text = clip.stringValue else { return nil }
        return ClipEntry(string: text)
    }
}
```

The JavaScript engine registers user scripts as actions conforming to the same protocol, with the script evaluated at invocation time.

---

## 12. Architecture Pattern — Migrate from Singletons + KVO to MVVM + Combine

### Current Design

All coordination flows through mutable singletons (`AppController`, `ClipsController`, `MenuController`, `ActionController`). Communication uses KVO and `NSNotificationCenter`. There are no formal ownership boundaries.

### Proposed Solution

Adopt a layered MVVM architecture:

```
View Layer (SwiftUI)
    ClipMenuView, PreferencesView, SnippetEditorView
        ↕  @Observable / @Query

ViewModel Layer
    ClipMenuViewModel — mediates between views and services
    SnippetEditorViewModel

Service Layer (Actors)
    ClipsService    — pasteboard monitoring, clip CRUD
    ActionService   — action node tree, script execution
    SnippetService  — snippet CRUD

Infrastructure Layer
    ClipboardMonitor    — NSPasteboard KVO → publisher
    HotkeyService       — KeyboardShortcuts registration
    PasteService        — CGEvent paste
    SettingsStore       — @AppStorage wrappers
```

Services communicate via `AsyncStream` or `Combine` publishers. The view layer never touches services directly; it goes through ViewModels. This makes each layer independently testable.

### Testing Impact

- `ClipsService` can be tested with an in-memory `ModelContainer` (`isStoredInMemoryOnly: true`).
- `ClipboardMonitor` can be injected with a mock that publishes synthetic changes.
- Action scripts can be run in isolation against a stub `JSContext`.
- No globals means tests run in parallel without interference.

---

## Summary Table

| # | Area | Current | Proposed | Min macOS |
|---|---|---|---|---|
| 1 | Clipboard monitoring | NSTimer polling (0.75 s) | NSPasteboard KVO | 10.8 |
| 2 | Clip persistence | NSKeyedArchiver | SwiftData (SQLite) | 14.0 |
| 2 | Snippet persistence | Core Data XML | SwiftData (shared container) | 14.0 |
| 3 | Concurrency | NSThread / NSOperationQueue | async/await + Actor | 13.0 |
| 4 | Global hotkeys | PTHotKeys (Carbon) | KeyboardShortcuts (CGEventTap) | 12.0 |
| 5 | UI | NSMenu + XIB | SwiftUI MenuBarExtra | 13.0 |
| 6 | JS engine | WebView (deprecated) | JavaScriptCore JSContext | 10.5 |
| 7 | App exclusion | GetFrontProcess (Carbon) | NSWorkspace.frontmostApplication | 10.7 |
| 8 | Login items | LSSharedFileList (deprecated) | SMAppService | 13.0 |
| 9 | Paste | CGEvent keycode scan | CGEvent with cached keycode | — |
| 10 | Settings | Manual NSUserDefaults + KVO | @AppStorage + Combine | 14.0 |
| 11 | Script actions | Filesystem walk + plist | Swift protocol + JS plugin | — |
| 12 | Architecture | Singletons + KVO | MVVM + Combine + Actors | 13.0 |

### Recommended Phasing

**Phase 1 — Drop in, no UI changes:**  
Items 1, 6, 7, 8, 9 — replace deprecated/polling APIs. These are self-contained and do not require architecture changes.

**Phase 2 — Data layer:**  
Items 2, 3, 10 — replace persistence with SwiftData and adopt async/await. Write migration routines for existing user data.

**Phase 3 — Full modernisation:**  
Items 4, 5, 11, 12 — SwiftUI, hotkey package, protocol-based actions. This is a full rewrite of the UI and coordination layers.
