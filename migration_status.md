# ClipMenu Migration Status

> **Every agent that completes a migration step MUST update this file before committing.**
> See `.github/copilot-instructions.md` for the full rule.

**Overall progress:** Phase 1 complete — Phase 2 complete — Phase 3 complete — Phase 4 complete (actions execution path implemented end-to-end: default action seeding, bundled scripts resources, contextual modifier-click popup dispatch inside clip-menu context, JS require path compatibility, numeric key equivalents in native popup, dedicated actions shortcut/menu while preserving snippets shortcut UX, Actions preferences CRUD editor with balanced native macOS UX, drag/drop tree organization, and folder-grouped JavaScript catalog browsing in Actions preferences; build passes) — post-migration repository cleanup complete (legacy tree and historical release tooling removed)

---

## Completed
 - [x] Removed obsolete General settings: `autosaveDelay` and clipboard `pollingInterval` controls were removed from preferences, corresponding `ClipMenuSettings` fields/defaults were deleted, and `ClipsService` now starts clipboard monitoring without a user-configurable interval dependency
 - [x] Phase 4 action runtime wiring: added first-launch default action seeding (built-ins + discovered JavaScript actions from bundle/user script folders) and root-action queries in `ActionService` so fresh installs have runnable actions without legacy `actions.plist`
 - [x] Phase 4 action invocation path: `ClipMenuItem` now evaluates modifier-click behavior, shows a native action popup menu (`ActionMenuBuilder`) when configured, supports direct configured action dispatch, and invokes action immediately when enabled with a single root leaf
 - [x] Phase 4 script resources + lookup parity: copied legacy `resource/script` tree into `Resources/scripts`, wired it in `project.yml` resources, updated `ScriptEngine` library lookup to support both `script/lib` and `scripts/lib`, regenerated project, and validated build success
 - [x] Phase 4 numeric key equivalents parity: native hotkey popup history items now assign numeric key equivalents (0-9) when enabled in settings
 - [x] Phase 4 Actions preferences editor expanded: `ActionsPrefsView` now includes a live SwiftData action-tree editor with root/folder hierarchy display, enable toggles, catalog-based insertion (Built-in / JavaScript / User scripts), folder creation, rename, delete, and sibling reordering controls
 - [x] Actions panel native UX/balance pass: left and right columns now keep equal width across resize via geometry-based layout, tree selection uses native `List(selection:)` behavior (no custom selection painting), and action controls use macOS-style small bordered icon+label buttons
 - [x] Phase 4 drag/drop parity: `ActionsPrefsView` now supports drag-and-drop action tree reordering and drag-into-folder organization, including safe ancestor checks and persisted sibling sort-index normalization
 - [x] Phase 4 modifier behavior picker parity: modifier-click pickers now include direct "Run <action>" options backed by serialized action payloads (builtin and JavaScript), in addition to no-action and popup-menu modes
 - [x] Action popup context fix: modifier-triggered action menus from clip rows are now anchored to the active clip-menu event/window content view rather than detached screen-position popups
 - [x] Hotkey parity extension: added a dedicated global shortcut/menu for actions (`⌘⇧A`) and integrated it in `HotkeyService` + `ShortcutsPrefsView` while preserving existing snippets shortcut UX (`⌘⇧B`)
 - [x] JavaScript catalog folder parity: `ActionsPrefsView` now renders JavaScript/User script catalogs as hierarchical folder trees (instead of a flat list) so insertion browsing matches bundled script structure
 - [x] Main menu Actions visibility parity: `ClipMenuView` now renders an `Actions` submenu in the status-bar menu (when actions are enabled), with clear empty states for no clips / no configured actions
 - [x] Contextual popup Actions parity: main hotkey/contextual `NSMenu` now includes an `Actions` submenu (when actions are enabled), matching status-menu availability while preserving the dedicated actions-only shortcut menu
 - [x] Contextual menu crash fix: prevented `NSInternalInconsistencyException` from re-inserting `NSMenuItem` instances already attached to another menu by assigning built action menus directly as submenus (or transferring items with explicit detach before re-add)
 - [x] Action execution behavior parity: action invocations now follow apply -> copy-as-new-item -> optional paste flow by inserting transformed string results as a new top clipboard history entry, syncing that entry to pasteboard, and synthesizing paste only in paste-capable invocation paths
 - [x] Action application reliability follow-up: hotkey/contextual action invocations now run transform-first in menu context and then perform the same front-app handoff paste path used by clip/snippet selection, improving visible action application during global-shortcut workflows
 - [x] JavaScript action bridge compatibility fix: `ScriptEngine` now exposes `ClipMenu.require()` with a boolean success return (legacy-compatible) and `ClipMenu.activate()` so bundled scripts like `Case/Capitalize.js` can load libraries and execute instead of throwing on falsy require results
 - [x] JavaScript library resolution parity: `ScriptEngine` `require` lookup now tries both raw relative paths and implicit `.js` extension paths (legacy behavior), fixing bundled actions that load `inflection` and `v8cgi/util` (e.g. `Capitalize`, `Calculate MD5 hash`)
 - [x] Action menu selector hardening: switched `ActionMenuTarget` to an explicit ObjC selector (`handleMenuItemAction:`) for NSMenu dispatch to avoid unrecognized-selector crashes during contextual/hotkey action-item invocation
 - [x] Preferences tab-strip hit-target parity: custom tabs now use full-width tab cells with explicit rectangular content shapes so clicks register across the entire tab area (not text-only)
 - [x] Snippets styling refinement: panel backgrounds normalized to `black.opacity(0.1)` and content editor made visually unified with the same card background by hiding the default scroll/content fill
 - [x] Snippets editor controls aligned to macOS conventions: folder/snippet add/remove actions now use compact `+`/`−` controls positioned under each list instead of text buttons
 - [x] Snippets editor visual refresh: removed harsh split dividers and restyled the three-column editor into rounded, darker panel cards for folders, snippet titles, and content while preserving existing rename/selection/edit behaviors
 - [x] Signing configuration persistence: copied `DEVELOPMENT_TEAM` (`WTWBLR82TY`) from generated project back into `project.yml` so `xcodegen generate` preserves team-based signing settings
 - [x] Project packaging fix: set `INFOPLIST_KEY_LSApplicationCategoryType` to `public.app-category.utilities` and moved `Assets.xcassets` into explicit `sources` entry with `buildPhase: resources` so asset catalog is compiled into the app (`Assets.car` present in built bundle)
 - [x] Permission prompt behavior refined: `PasteService` no longer invokes `AXIsProcessTrustedWithOptions` re-prompts each app session; it now checks trust only and logs missing permission once per session, avoiding repeated prompt popups on app open
 - [x] Regression fix: history menus now honor configured history cap in both SwiftUI status menu and native hotkey popup (capped to `maxHistorySize`), and startup now enforces trimming immediately
 - [x] Regression fix: `ClipsService` moved to `@MainActor` isolation so pasteboard + SwiftData `mainContext` operations execute on the correct thread, preventing menu-selection paste crash path
 - [x] Image clip rendering parity improved: image-only clips now use `(Image)` fallback title and show scaled thumbnails in both SwiftUI menu rows and native hotkey popup history menus
- [x] Image thumbnail robustness improved: thumbnail decoding now falls back to `NSBitmapImageRep` and uses fixed-canvas aspect-fit scaling, improving preview rendering for edge-case image clipboard data
- [x] App-menu image preview parity fix: SwiftUI clip rows now prioritize thumbnail rendering over type icons, resolving cases where app menu showed only a document icon instead of the image preview
- [x] Added diagnostics logging for image preview troubleshooting across capture and rendering paths (`ClipsService`, `ClipMenuItem`, `HotkeyService`) including image byte capture, decode path, and thumbnail attachment outcomes
- [x] Snippets preferences visual polish: added vertical inset around the 3-column split view so divider lines have top/bottom padding instead of touching window edges
- [x] Hotkey paste reliability pass: hotkey popup now records the pre-popup frontmost app and re-activates it before selection-triggered paste; popup anchor window no longer tries to become key (removes borderless key-window warning source)
- [x] Hotkey paste timing hardening: for popup selections, copy now occurs without immediate paste, then Cmd+V is dispatched after focus handoff delays; added `PasteService` guard-result logging (AX trust/keycode/event source/post)
- [x] Accessibility trust hardening: when AX trust is false, `PasteService` now requests system prompt via `AXIsProcessTrustedWithOptions` (once/session) and logs bundle/executable identity for TCC mismatch diagnosis
- [x] Bundle identity updated for downstream signing/distribution: `PRODUCT_BUNDLE_IDENTIFIER` changed from `com.naotaka.ClipMenu` to `app.eetr.ClipMenu`
- [x] App icon pipeline completed: generated all required macOS `AppIcon.appiconset` sizes (16/32/128/256/512 @1x/@2x) from the provided 1024x1024 source image and wired filenames in asset catalog `Contents.json`
 - [x] Repository cleanup: removed `legacy/` Objective-C tree and historical release/documentation artifacts (`script/deploy.sh`, appcast/version-history generators, old HTML/YAML release notes, and archived legacy docs), then updated root docs to the modern Swift/XcodeGen workflow
- [x] Legacy Objective-C reference tree was retained during migration and removed after migration completion as part of repository cleanup

### New project bootstrapped
- [x] `Sources/` tree created with stub Swift files (no implementation yet)
- [x] `Assets.xcassets/` with `AppIcon.appiconset`
- [x] `ClipMenu.entitlements` (non-sandboxed, CGEvent automation)
- [x] `project.yml` (XcodeGen spec) — macOS 14.0, Swift 5.9, bundle ID `com.naotaka.ClipMenu`
- [x] `ClipMenu.xcodeproj` generated via `xcodegen generate`
- [x] Build confirmed: project generates without errors

### Documentation
- [x] `BUILD.md` added with modern build commands and legacy release-script notes

---

## In Progress

No tasks currently in progress.

---

## Completed

### Phase 2 — UI

- [x] `ScriptEngine` — JSContext bridge with `clipText`/`clip` globals and `ClipMenu.require()` loader
- [x] `ScriptableClip` — `JSExport` bridge: `text`, `setStringAttributes(_:)`, `addStringAttributes(_:)`, CSS color extension
- [x] `ClipMenuApp` — `MenuBarExtra` + `Settings` scenes wired; `EnvironmentKeys.swift` with service environment keys
- [x] `ClipMenuView` — full history section (inline + folder groups), snippet section (above/below/hidden), clear history, preferences + quit items; `#Preview`
- [x] `ClipMenuItem` — type icon via `NSWorkspace`, thumbnail scaling, trimTitle(), numbering, labels, tooltip, font size, `#Preview`
- [x] `SnippetSection` — enabled folders, single-snippet inline / multi-snippet submenu, paste on select; `#Preview`
- [x] `ActionSection` — folder + leaf node rendering, action dispatch; `#Preview`
- [x] `GeneralPrefsView` — login item, clipboard prefs, store-types grid, exclude-apps editor; `#Preview`
- [x] `MenuPrefsView` — title length, inline/folder counts, numbering, labels, clear-history, tooltips, font size, images, icons; `#Preview`
- [x] `ActionsPrefsView` — enable toggle, modifier-click pickers, invoke-immediately; `#Preview`
- [x] `ShortcutsPrefsView` — `KeyboardShortcuts.Recorder` controls for all three shortcuts (⌘⇧V, ⌘⌃V, ⌘⇧B); `#Preview`
- [x] `PreferencesView` — tab shell; `#Preview`
- [x] `SnippetsPrefsView` — migrated snippets settings/editor surface (folder/snippet CRUD + enable toggles + content editing); `#Preview`
- [x] `LegacyMigration` — snippet import from `Snippets.xml` added (Core Data XML → SwiftData)
- [x] `SnippetService.paste(snippet:)` — implemented (write to pasteboard + `PasteService.paste()`)
- [x] `ActionService` — builtin actions (`removeAction`, `pasteAsPlainText`, `pasteAsFilePath`, `pasteAsHFSFilePath`); JS script dispatch via `ScriptEngine`
- [x] `ClipsService.clearAll()` and `ClipsService.copyStringToPasteboard(_:)` added

### Phase 3 — Hotkeys + Polish

- [x] `HotkeyService` — `KeyboardShortcuts.Name` extensions (`.openClipMenu` ⌘⇧V, `.openHistory` ⌘⌃V, `.openSnippets` ⌘⇧B) with default combos matching legacy PTHotKey defaults; `register()` / `unregister()` implemented; activates `MenuBarExtra` via KVC status-item lookup + `performClick`
- [x] `AppRuntime` — `hotkeyService: HotkeyService` added
- [x] `AppDelegate` — `hotkeyService.register()` called in `applicationDidFinishLaunching`; `hotkeyService.unregister()` called in `applicationWillTerminate`
- [x] `ShortcutsPrefsView` — `KeyboardShortcuts.Recorder` controls for all three shortcuts (⌘⇧V, ⌘⌃V, ⌘⇧B); `#Preview`
- [x] Build passes (one deprecation warning for `icon(forFileType:)`, no errors)
- [x] `ClipMenuSettings` persistence hardened: replaced `@AppStorage` + `@ObservationIgnored` fields with explicit `UserDefaults`-backed observed properties, added startup reload and value sanitization for stable defaults and app-launch behavior
- [x] `AppDelegate` now calls `settings.reload()` during launch before services start, ensuring settings are loaded/normalized before initial menu and clipboard service usage
- [x] Accessibility prompt no longer triggers unconditionally at launch; permission prompt is now lazy via paste path (`PasteService`) and startup no longer opens System Settings repeatedly
- [x] Settings reload now uses typed fallback defaults (`object(forKey:)` with explicit defaults) rather than raw `bool/integer` reads, improving launch-time hydration correctness when keys are missing or malformed
- [x] SwiftData environment wiring hardened for menu startup: `ClipMenuApp` now injects `.modelContainer(modelContainer)` directly into `ClipMenuView` and `PreferencesView` roots to avoid `@Query` modelContext-missing errors on initial load
- [x] Paste actions no longer force Accessibility permission prompts on each click; `PasteService` now checks `AXIsProcessTrusted()` without opening System Settings, preventing repetitive prompt spam during menu usage
- [x] Hotkey registration reliability improved: `HotkeyService` now dispatches menu activation on the main thread and uses resilient status-item lookup (`statusItems`/`_statusItems`) so Cmd+Shift+V / Cmd+Shift+B consistently open the menu
- [x] Hotkey bootstrap hardening: `HotkeyService.register()` now restores default shortcuts when persisted entries are missing/disabled, preventing inactive Cmd+Shift+V / Cmd+Shift+B on launch
- [x] Hotkey trigger path hardened further: switched handlers to key-down events and made menu activation retry on main-thread with app activation before status-item click, improving global shortcut responsiveness when app is backgrounded
- [x] Launch-order fix: `AppDelegate` now registers hotkeys independently of SwiftData readiness and retries data-service startup until `modelContainer.mainContext` exists, preventing silent startup paths where shortcuts/services were skipped
- [x] Hotkey menu presentation refined: shortcuts now trigger on key-up, menu activation is deferred to next runloop, forced app activation was removed, and status-item targeting/click fallback logic was strengthened to prevent focus-steal without menu display
- [x] Hotkey presentation simplified to one UI path: shortcuts now always open a native `NSMenu` popup at cursor (no status-item click injection, no secondary fallback UI), matching legacy interaction and arrow-key navigation expectations
- [x] Added structured hotkey diagnostics logging (`Logger`) across registration, trigger handling, status-item lookup retries, menu-open detection, and fallback-popup presentation to accelerate runtime troubleshooting
- [x] Fixed hotkey retry exhaustion path: when no status-item button is found after all retries, `HotkeyService` now calls completion with failure so fallback panel presentation always executes
- [x] Fallback panel presentation polished: replaced collapsed non-activating panel layout with a fixed-size utility panel and wrapped SwiftUI root (`FallbackPanelRootView`) so hotkey fallback UI renders at readable width/height
- [x] Snippets menu discoverability parity: added `Edit Snippets…` entry to both SwiftUI status menu and hotkey popup menu, opening Preferences directly on the Snippets tab
- [x] Preferences window UX improved: custom AppKit preferences window is now resizable and opens at a larger default size with enforced minimum content size
- [x] Snippets menu structure parity: snippet folders now always render as submenus (including single-snippet folders) in both status menu and hotkey popup menu
- [x] Snippets settings UX improved: selected folder can now be renamed directly in `SnippetsPrefsView`
- [x] Snippets settings parity pass: `SnippetsPrefsView` now uses a classic 3-column macOS layout (Folders / Titles / Content), supports folder rename on double-click, and exposes snippet-position placement (above/below/hidden) directly in the Snippets tab
- [x] Snippets rename/edit parity improved: snippet titles now support inline rename on double-click (same interaction model as folders), and the Snippets tab layout is now responsive with adaptive top controls and resizable split columns
- [x] Preferences/navigation polish: custom preferences tabs now use explicit SF Symbol icons in the tab strip for consistent icon visibility in the AppKit-hosted settings window
- [x] Menu bar icon polish: switched MenuBarExtra label to a cleaner SF Symbol with explicit menu-bar sizing/weight for better visual fit
- [x] Main app menu icon polish: added SF Symbol icons for top-level command items (Clear History, Edit Snippets, Preferences, Quit) in both SwiftUI status menu and native hotkey popup menu
- [x] Preferences tab-strip focus polish: replaced custom button row with native segmented control using SF Symbols to eliminate distracting focus outline artifacts
- [x] Preferences tab-strip icon parity restored: reintroduced SF Symbol icons in the custom tab strip while suppressing focus-ring artifacts via non-focusable plain tab buttons
- [x] Menu grouping icon parity: history range groups and snippet folder groups now show folder icons in the main SwiftUI status menu

---

## Key Decisions (do not revisit without updating this section)

| Decision | Value | Rationale |
|---|---|---|
| Bundle ID | `app.eetr.ClipMenu` | Updated app identity for downstream signing/distribution; existing defaults migration remains key-based |
| Deployment target | macOS 14.0 | Minimum required for SwiftData |
| Swift version | 5.9+ | SwiftData, @Observable, structured concurrency |
| Sandboxing | **No sandbox** | CGEvent paste requires Accessibility; incompatible with sandbox |
| External deps | `KeyboardShortcuts` only | All other APIs are system-provided |
| Legacy data location reference | Removed from repository in post-migration cleanup | Migration import work completed before cleanup |

---

## Reference Files

| What to check | Where |
|---|---|
| Full architecture plan | `doc/migration.md` |
| All features to preserve | `doc/features.md` |
| Legacy clipboard behavior | Historical legacy sources (removed from repo) |
| Legacy menu behavior | Historical legacy sources (removed from repo) |
| Legacy action system | Historical legacy sources (removed from repo) |
| Legacy JS integration | Historical legacy sources (removed from repo) |
| Legacy preferences keys | Historical legacy sources (removed from repo) |
| Snippet/action data paths | Historical legacy sources (removed from repo) |
