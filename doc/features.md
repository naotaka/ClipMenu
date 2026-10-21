# ClipMenu — Feature & Architecture Reference

This document is intended to give an LLM (or a developer) enough context to understand, extend, or reconstruct the application from the existing source code. It covers every major feature, the data model, the component wiring, key algorithms, preference keys, and file formats.

---

## Overview

ClipMenu is a macOS clipboard manager written in Objective-C (manual reference counting, targeting Mac OS X 10.5+). It runs as a background process that never appears in the Dock. Its only persistent UI element is a status-bar icon. The user interacts through pop-up menus triggered by global hotkeys or by clicking the status item.

Bundle ID: `com.naotaka.ClipMenu`  
Version: 0.4.4a13  
License: MIT

---

## High-Level Architecture

```
AppController          (main controller — owns hotkeys, actions, preference panel)
├── ClipsController    (singleton — pasteboard monitoring, clip storage)
├── MenuController     (singleton — status item, all pop-up menus)
├── ActionController   (singleton — JavaScript engine, built-in actions)
│   └── BuiltInActionController
└── SnippetsController (singleton — Core Data store for snippets)
    └── SnippetEditorController
```

All singletons use `+initialize`/`+sharedInstance` with a module-level static variable. They are NOT thread-safe; all mutations run on the main thread except autosave which detaches a new thread via `NSThread detachNewThreadSelector:`.

### Startup Sequence (`applicationDidFinishLaunching:`)

1. Create an `NSOperationQueue` and enqueue three concurrent operations:
   - `[ClipsController loadClips]` — deserialise `clips.data`
   - `[ActionController loadActions]` — parse `actions.plist`
   - `[AppController _registerHotKeys]` — register global hotkeys via PTHotKeyCenter
2. Prompt user to add login item (once, suppressed by `CMPrefSuppressAlertForLoginItemKey`).
3. Configure Sparkle updater (feed URL, auto-check flag, interval).
4. Wait for all operations to finish.

### Shutdown Sequence (`applicationWillTerminate:`)

1. If `CMPrefSaveHistoryOnQuitKey` is YES, call `[ClipsController saveClips]`; else call `[ClipsController removeClips]` (deletes the file).
2. Call `[ActionController saveActions]`.
3. Unregister all hotkeys.

### KVO Wiring

`AppController` observes:
- `CMPrefHotKeysKey` → re-registers all hotkeys
- `CMEnableAutomaticCheckPreReleaseKey` → switches Sparkle feed URL

`ClipsController` observes:
- `CMPrefMaxHistorySizeKey` → trims history
- `CMPrefAutosaveDelayKey` → restarts autosave timer
- `CMPrefTimeIntervalKey` → restarts pasteboard polling timer
- `CMPrefStoreTypesKey` → reloads which types to capture
- `CMPrefExcludeAppsKey` → reloads exclude bundle-ID set

`AppController` also observes `ClipsController.clips` (KVO key `"clips"`). Any change triggers `[MenuController updateStatusMenu]` so the menu stays current.

---

## Data Model: `Clip`

`Clip` (`Source/Clip.m`) is an `NSObject` that implements `NSCoding` and `NSCopying`.

### Properties

| Property | Type | NSCoder key |
|---|---|---|
| `types` | `NSArray *` (of pasteboard type strings) | `"types"` |
| `createdDate` | `NSDate *` | `"createdDate"` |
| `lastUsedDate` | `NSDate *` | `"lastUsedDate"` |
| `stringValue` | `NSString *` | `"stringValue"` |
| `RTFData` | `NSData *` | `"RTFData"` |
| `PDF` | `NSData *` | `"PDF"` |
| `filenames` | `NSArray *` (of `NSString`) | `"filenames"` |
| `URL` | `NSArray *` (of `NSString`) | `"URL"` |
| `image` | `NSImage *` | `"image"` |
| `thumbnail` | `NSImage *` (transient, not encoded) | — |

**Backward-compat decoding:** `lastUsedDate` falls back to key `"lastAccessedDate"` (used in v0.4.2a2–a4). `RTFData` falls back to keys `"RTFD"` then `"RTF"`.

### Identity / Equality

`hash` is computed from the `types` array string, then XOR-ed with:
- Image: TIFF byte length
- Filenames: XOR of each filename's hash
- URL: XOR of each URL string hash
- PDF: byte length
- stringValue: `NSString` hash
- RTFData: byte length (if present)

`isEqual:` delegates entirely to `hash` comparison.

### Supported Pasteboard Types

Defined in `+availableTypes` (order matters for `primaryPboardType`):

```
NSStringPboardType, NSRTFPboardType, NSRTFDPboardType, NSPDFPboardType,
NSFilenamesPboardType, NSURLPboardType, NSTIFFPboardType, NSPICTPboardType
```

Human-readable names from `+availableTypeNames`:
`String, RTF, RTFD, PDF, Filenames, URL, TIFF, PICT`

Both lists are parallel arrays; `+availableTypeDictionary` returns a dict mapping pasteboard type → name.

### Thumbnail

`-thumbnailOfSize:(NSSize)size` scales the image to fit within the given bounding box while preserving aspect ratio. The result is cached (invalidated if requested size differs). Uses `bestRepresentationForRect:context:hints:` on 10.6+, falls back to a manual `NSBitmapImageRep` draw into a new `NSImage`.

---

## ClipsController

`Source/ClipsController.m` — singleton.

### State

- `clips` — `NSMutableSet` of `Clip` objects (KVO-observable)
- `storeTypes` — `NSDictionary` mapping type-name → `NSNumber(BOOL)`
- `excludeIdentifiers` — `NSSet` of bundle-identifier strings to ignore
- `maxClipsSize` — `NSUInteger`
- `cachedChangeCount` — `NSInteger`; mirrors `[NSPasteboard generalPasteboard].changeCount`
- `lastClipsUpdated`, `lastSaved` — `NSDate` used by autosave logic

### Pasteboard Polling

`_startPasteboardObservingTimer` creates a repeating `NSTimer` at the configured interval (max capped at 1.0 s). On each tick, `_updateClips:` runs:

1. Read `[NSPasteboard generalPasteboard].changeCount`. If unchanged, return.
2. Cache the new change count.
3. Check `_frontProcessIsInExcludeList` via `GetFrontProcess` + `ProcessInformationCopyDictionary`. If excluded, return.
4. Call `_makeClipFromPasteboard:` to build a new `Clip`.
5. If the set already contains an equal clip (by hash), update its `lastUsedDate` and return.
6. Add the new clip via `mutableSetValueForKey:@"clips"` (triggers KVO).
7. Call `_trimHistorySize`.

`_makeClipFromPasteboard:` first calls `_makeTypesFromPasteboard:` to build the list of types to store (filtered by `storeTypes`; TIFF and PICT are collapsed to TIFF). It then reads each type's data from the pasteboard.

### History Trimming

`_trimHistorySize` sorts clips by `sortedClips` (newest first), then removes the tail items that exceed `maxClipsSize`.

### Sorted View

`sortedClips` (dynamic property) sorts by `lastUsedDate` descending when `CMPrefReorderClipsAfterPasting` is YES, or by `createdDate` descending otherwise.

### Persistence

- **File:** `~/Library/Application Support/ClipMenu/clips.data`
- **Format:** `NSKeyedArchiver` archive of the `sortedClips` array
- **Save:** `saveClips` — writes via `NSKeyedArchiver archiveRootObject:toFile:`
- **Load:** `loadClips` — unarchives, sets `clips`, trims to max size
- **Delete:** `removeClips` — removes the file from disk (called on quit when save-on-quit is off)

### Autosave

A second repeating timer fires at `CMPrefAutosaveDelayKey` seconds (min 15 s). `_autosave` compares `lastSaved` vs `lastClipsUpdated`. If clips have been updated since last save, it detaches a new thread to call `_fireSaveClips`, which calls `saveClips` and updates `lastSaved` on success. On failure, it shows an alert and restarts the timer.

### Export

- `exportHistoryStringsAsSingleFile:path` — concatenates all text clips with a configurable separator (newline, CRLF, CR, tab, space, or empty). Uses `NSFileHandle` to append each clip.
- `exportHistoryStringsAsMultipleFiles:path` — writes each text clip to a numbered `.txt` file (e.g. `1.txt`, `2.txt`, …) in the given directory.

Only clips containing `NSStringPboardType` are exported. Non-text clips are silently skipped.

### Public Mutation API

- `copyClipToPasteboard:(Clip *)clip` — writes all of the clip's types back to `[NSPasteboard generalPasteboard]`
- `copyClipToPasteboardAtIndex:(NSUInteger)index` — index into `sortedClips`
- `copyStringToPasteboard:(NSString *)aString` — writes a plain string
- `removeClip:(Clip *)` / `removeClipAtIndex:` — remove from the set (KVO-notified)
- `clearAll` — removes all objects (KVO-notified)

---

## MenuController

`Source/MenuController.m` — singleton.

### Menu Types

```objc
typedef enum {
    CMPopUpMenuTypeMain,
    CMPopUpMenuTypeHistory,
    CMPopUpMenuTypeSnippets,
    CMPopUpMenuTypeActions
} CMPopUpMenuType;
```

`popUpMenuForType:` constructs the appropriate menu and pops it up near the mouse cursor.

### Status Item

`createStatusItem` creates an `NSStatusItem` with icon `StatusMenuIcon.png` (normal) / `StatusMenuIcon_pressed.png` (highlighted). The menu is rebuilt on each open via `updateStatusMenu`.

### Menu Construction

`_buildClipMenu` produces the main clip menu:

1. Add "Open Snippet Editor" and "Preferences" items.
2. Add a separator.
3. Optionally add snippets **above** clips (`CMPositionOfSnippetsAboveClips`).
4. Add clips via `_addClipsToMenu:`.
5. Optionally add snippets **below** clips (`CMPositionOfSnippetsBelowClips`).
6. Optionally add a "Clear History" item.

`_addClipsToMenu:` iterates `[ClipsController sortedClips]`. For each clip it calls `_makeMenuItemForClip:withCount:andListNumber:`.

**Inline vs. folder display:**
- `CMPrefNumberOfItemsPlaceInlineKey` clips appear directly in the menu.
- Remaining clips are grouped into submenus of size `CMPrefNumberOfItemsPlaceInsideFolderKey`, with a title like "11-20".
- If both prefs are 0, all clips appear inline.

### Menu Item Construction (`_makeMenuItemForClip:`)

1. Determine title:
   - `trimTitle()` — strips leading/trailing whitespace, extracts first line, truncates to `CMPrefMaxMenuItemTitleLengthKey` chars with `"..."` suffix.
   - If `CMPrefMenuItemsAreMarkedWithNumbersKey`, prefix with `"<n>. "` (number starts at 0 or 1 per `CMPrefMenuItemsTitleStartWithZeroKey`, wraps 10→0 when starting from 1).
2. If `CMPrefShowLabelsInMenuKey`, append the primary pasteboard type label.
3. For image clips, if `CMPrefShowImageInTheMenuKey`, use a thumbnail (`CMPrefThumbnailWidthKey` × `CMPrefThumbnailHeightKey`) as the menu item image.
4. If `CMPrefShowIconInTheMenuKey`, use `[Clip fileTypeIconForPboardType:]` scaled to `CMPrefMenuIconSizeKey` pixels as a leading icon.
5. If `CMPrefChangeFontSizeKey`, wrap the title in an `NSAttributedString` with the configured font size (auto: match icon size; manual: `CMPrefSelectedFontSizeKey`).
6. If `CMPrefShowToolTipOnMenuItemKey`, set a tooltip to the first `CMPrefMaxLengthOfToolTipKey` characters.
7. If `CMPrefAddNumericKeyEquivalentsKey`, set key equivalent to `"1"`…`"9"`, `"0"` for items 1–10.
8. Set `tag` = clip index in `sortedClips`. Set `action = @selector(selectMenuItem:)`, `target = AppController`.

### Snippet Items

Each enabled snippet in an enabled folder gets a menu item with `action = @selector(selectSnippetMenuItem:)` and `representedObject = NSManagedObject`.

### Action Menu

Built from `[ActionController actionNodes]` (a flat/tree list of `ActionNode`). Each leaf node becomes a menu item; container nodes become submenus. Items are filtered through `CMIsPerformableAction()` before being shown. `CMIsPerformableAction` checks the selected clip's types against the action's declared applicable types.

### `trimTitle()` — title trimming function

```
1. NSString *strip — calls [clipString strip] (whitespace trim, defined in NSString+NaoAdditions)
2. getLineStart:end:contentsEnd:forRange: to find first line
3. If multi-line, truncate to contentsEnd
4. If length > maxMenuItemTitleLength, truncate to (max - 3) and append "..."
```

---

## AppController

`Source/AppController.m` — loaded from MainMenu.xib.

### Menu Item Selection

**`selectMenuItem:sender`** (clips):
1. Call `_applyActionToTarget:sender`. If an action was applied, return.
2. Otherwise call `[ClipsController copyClipToPasteboardAtIndex:[sender tag]]`.
3. Call `[CMUtilities paste]`.

**`selectSnippetMenuItem:sender`** (snippets):
1. Call `_applyActionToTarget:sender`. If an action was applied, return.
2. `copyStringToPasteboard:` the snippet's `content`.
3. `[CMUtilities paste]`.

**`selectActionMenuItem:sender`**:
1. Get `NSDictionary *action` from `representedObject`.
2. Call `_invokeAction:`.

### Modified-Click Detection (`_applyActionToTarget:`)

Reads `[NSApp currentEvent]` modifier flags at the moment of selection:

| Condition | Preference key |
|---|---|
| Right-click or Ctrl held | `CMPrefContorlClickBehaviorKey` |
| Shift held | `CMPrefShiftClickBehaviorKey` |
| Option held | `CMPrefOptionClickBehaviorKey` |
| Cmd held | `CMPrefCommandClickBehaviorKey` |

The preference value is either:
- `kEmptyString` — no override
- `kPopUpActionMenu` — pop up the action selection menu
- `NSDictionary` (an action descriptor) — invoke that action directly

### Action Invocation Flow

`_invokeAction:action toIndex:index`:
- `index < 0` → target is `[ActionController selectedSnippet]` (a snippet `NSManagedObject`)
- `index >= 0` → target is `[ClipsController clipAtIndex:index]`
- Dispatches to `_invokeBuiltinAction:toTarget:` or `_invokeJavaScriptAction:atIndex:`

`_invokeBuiltinAction:toTarget:` looks up the selector from `BuiltInActionController.actions[name]["actionName"]` and calls it via `performSelector:withObject:`.

`_invokeJavaScriptAction:atIndex:`:
1. Gets the script path from the action dict.
2. Wraps the clip in a `ScriptableClip`.
3. Calls `[ActionController invokeScript:toClip:]`.
4. The result `Clip` is written back to the pasteboard.
5. `[CMUtilities paste]` is called.

### Paste Implementation (`CMUtilities +paste`)

Checks `CMPrefInputPasteCommandKey`. If YES, calls `postCommandV()`:
1. First call: scans all key codes 0–127 via `UCKeyTranslate` (TIS) to build a `string→keyCode` map and cache the keyCode for "V".
2. Creates `CGEventRef` key-down and key-up with `kCGEventFlagMaskCommand`.
3. Posts both to `kCGSessionEventTap`.

### Process Management

Before popping a menu, `keepCurrentFrontProcessAndActivate` records `GetFrontProcess(&frontPSN)` and brings ClipMenu to the front. After the menu closes (or after a paste), `restorePreviousFrontProcess` calls `SetFrontProcess(&frontPSN)` to give focus back to the original app.

---

## ActionController

`Source/ActionController.m` — singleton.

### Initialization

On `_init`, creates a hidden `WebView` (no frame, loads empty HTML string) used as the JavaScript execution engine. Also creates `ActionNodeFactory` and `BuiltInActionController`.

The `WebView`'s policy delegate returns `[listener ignore]` for all navigation actions (prevents external resource access).

### Action Node Tree

Actions are stored as a flat `NSMutableArray` of `ActionNode` objects. Each node has:
- `title` — display name
- `isLeaf` — YES for executable actions, NO for folders/groups
- `children` — sub-nodes for folders
- `action` — `NSDictionary` for leaf nodes

Action `NSDictionary` structure:
```
{
  "type": "builtin" | "javaScript",
  "name": "<action key>",       // for builtins
  "path": "<script file path>"  // for JS actions
}
```

### Action Discovery

`prepareActions` (called by `loadActions` if no saved file exists) calls three methods:

1. `_prepareBuiltinActionNodes` — creates nodes for Remove, PasteAsPlainText, PasteAsFilePath, PasteAsHFSFilePath.
2. `_prepareBundledScriptActionNodes` — walks `ClipMenu.app/Contents/Resources/script/action/` and creates a node for each `.js` file.
3. `_prepareUsersScriptActionNodes` — walks `~/Library/Application Support/ClipMenu/script/action/` for user-added scripts.

### Persistence

- **File:** `~/Library/Application Support/ClipMenu/actions.plist`
- **Format:** XML property list — array of `ActionNode.dictionaryRepresentation`
- Legacy format: `actionMenu.data` (NSKeyedArchiver) — read but not written

### JavaScript Execution (`invokeScript:toClip:`)

1. Reads script content from disk.
2. Wraps script in: `function __wrapper(clipText, clip) { try { <script> } catch(e) { __scriptException = e.toString(); return; } }`
3. Gets `WebScriptObject *scriptObject = [webView windowScriptObject]`.
4. Sets `scriptObject["__scriptException"] = ""`.
5. Creates `JavaScriptSupport` and sets it as `scriptObject["ClipMenu"]`.
6. Creates `ScriptableClip` wrapping the input clip and sets it as `scriptObject["clip"]`.
7. Evaluates the wrapper definition.
8. Calls `[scriptObject callWebScriptMethod:@"__wrapper" withArguments:@[clipText, scriptableClip]]`.
9. Checks `__scriptException`. If non-empty, shows an alert and returns nil.
10. If result is `WebUndefined`, returns nil.
11. Otherwise interprets result as a string, creates a new `Clip` from it, returns it.

### JavaScript API Surface

Scripts receive two arguments: `clipText` (NSString) and `clip` (ScriptableClip).

`ScriptableClip` exposes to JS (via `WebScripting` protocol):
- `setStringAttributes(attrs)` — replace all attributes on the RTF/RTFD clip
- `addStringAttributes(attrs)` — add attributes to the clip

`attrs` is a JS object with optional keys:
- `color.foreground` — CSS color string
- `color.background` — CSS color string
- `font.name` / `font.size`
- `underline.style` ("none"|"single"|"thick"|"double"), `underline.pattern` ("solid"|"dot"|"dash"|"dashdot"|"dashdotdot"), `underline.byWord`

`JavaScriptSupport` exposes `ClipMenu.require(relativePath)` which reads a `.js` library from `script/lib/` (app bundle first, then user support folder) and evaluates it in the current WebView context.

### Built-in Actions (`BuiltInActionController`)

Each built-in is a selector on `BuiltInActionController`:

| Action key | Selector | Applicable types |
|---|---|---|
| `removeAction` | `remove:` | all types |
| `pasteAsPlainText:` | `pasteAsPlainText:` | `NSStringPboardType` |
| `pasteAsFilePath:` | `pasteAsFilePath:` | `NSFilenamesPboardType` |
| `pasteAsHFSFilePath:` | `pasteAsHFSFilePath:` | `NSFilenamesPboardType` |

`remove:` calls `[ClipsController removeClip:]` (for clips) or `[SnippetsController removeSnippet:]` (for snippets).  
`pasteAsPlainText:` creates a new `Clip` with only `NSStringPboardType`, copies to pasteboard, pastes.  
`pasteAsFilePath:` joins filenames with `\n`, creates text clip, pastes.  
`pasteAsHFSFilePath:` converts each POSIX path to HFS via `CFURLCopyFileSystemPath(..., kCFURLHFSPathStyle)`, joins, pastes.

---

## SnippetsController

`Source/SnippetsController.m` — singleton using Core Data.

### Data Model (`Snippets.xcdatamodel`)

Two entities:

**Folder**
- `title` (String)
- `enabled` (Boolean)
- `index` (Integer 16)
- `snippets` (to-many relationship → Snippet)

**Snippet**
- `title` (String)
- `content` (String)
- `enabled` (Boolean)
- `index` (Integer 16)
- `folder` (to-one relationship → Folder)

### Persistence

- **File:** `~/Library/Application Support/ClipMenu/Snippets.xml`
- **Format:** Core Data XML store (`NSXMLStoreType`)
- Coordinator and context are set up in `_init`. The persistent store is added lazily.

### Import/Export (XML)

`SnippetEditorController` supports import/export of snippets via a custom XML format (not Core Data's XML). Structure:
```xml
<folders>
  <folder>
    <title>Folder Name</title>
    <snippets>
      <snippet>
        <title>Snippet Name</title>
        <content>Snippet text</content>
      </snippet>
    </snippets>
  </folder>
</folders>
```

Constants: `kRootElement="folders"`, `kFolderElement="folder"`, `kSnippetElement="snippet"`, `kTitleElement="title"`, `kSnippetsElement="snippets"`, `kContentElement="content"`.

---

## Hotkey System

### PTHotKeys Library

Located in `Source/PTHotKeys/`. Provides:
- `PTKeyCombo` — wraps key code + modifier flags; serialises to/from plist dict
- `PTHotKey` — a single registered hotkey with target/action
- `PTHotKeyCenter` — singleton that registers/unregisters with the OS

### Hotkey Map (`CMUtilities +hotKeyMap`)

| Identifier | Index | Selector |
|---|---|---|
| `"ClipMenu"` | 0 | `popUpClipMenu:` |
| `"HistoryMenu"` | 1 | `popUpHistoryMenu:` |
| `"SnippetsMenu"` | 2 | `popUpSnippetsMenu:` |

### Default Key Combos

| Menu | Key code | Modifiers | Equivalent |
|---|---|---|---|
| Clip Menu | 9 (`V`) | 768 (`Cmd+Shift`) | `Cmd+Shift+V` |
| History Menu | 9 (`V`) | 4352 (`Cmd+Ctrl`) | `Cmd+Ctrl+V` |
| Snippets Menu | 11 (`B`) | 768 (`Cmd+Shift`) | `Cmd+Shift+B` |

### Registration Flow

`_registerHotKeys`:
1. Read `CMPrefHotKeysKey` from `NSUserDefaults`.
2. For each identifier in the default map, merge with saved combos (saved takes priority).
3. Create a `PTHotKey` with the identifier, combo, target=AppController, action from the hotKey map.
4. Register with `[PTHotKeyCenter registerHotKey:]`.

`_unregisterHotKeys` calls `unregisterHotKey:` for each hotkey in `[PTHotKeyCenter allHotKeys]`.

---

## Preferences System

All preference keys are prefixed `CMPref*` or `CM*`. Defaults are registered in `+[AppController initialize]`.

### File Storage Paths

| Data | Path |
|---|---|
| Clip history | `~/Library/Application Support/ClipMenu/clips.data` |
| Action nodes | `~/Library/Application Support/ClipMenu/actions.plist` |
| Snippets | `~/Library/Application Support/ClipMenu/Snippets.xml` |
| User scripts | `~/Library/Application Support/ClipMenu/script/action/*.js` |
| User script libs | `~/Library/Application Support/ClipMenu/script/lib/*.js` |
| Bundled scripts | `ClipMenu.app/Contents/Resources/script/action/` |
| Script libraries | `ClipMenu.app/Contents/Resources/script/lib/` |

### Complete Preference Key Reference

#### General

| Key | Type | Default | Description |
|---|---|---|---|
| `CMPrefLoginItemKey` | BOOL | NO | Launch on startup |
| `CMPrefSuppressAlertForLoginItemKey` | BOOL | NO | Don't ask again about login item |
| `CMPrefInputPasteCommandKey` | BOOL | YES | Auto-paste with Cmd+V after selection |
| `CMPrefReorderClipsAfterPasting` | BOOL | YES | Move used clip to top |
| `CMPrefMaxHistorySizeKey` | NSUInteger | 20 | Max number of clips |
| `CMPrefAutosaveDelayKey` | NSUInteger | 1800 | Autosave interval (seconds) |
| `CMPrefSaveHistoryOnQuitKey` | BOOL | YES | Save history when app quits |
| `CMPrefExportHistoryAsSingleFileKey` | BOOL | YES | Export as one file vs. many |
| `CMPrefTagOfSeparatorForExportHistoryToFileKey` | NSUInteger | 1 | 0=none,1=\n,2=\r\n,3=\r,4=\t,5=space |
| `CMPrefShowStatusItemKey` | NSUInteger | 1 | Show status bar icon |
| `CMPrefTimeIntervalKey` | float | 0.75 | Pasteboard polling interval (seconds, max 1.0) |
| `CMPrefStoreTypesKey` | NSDictionary | all YES | Per-type storage enable/disable |
| `CMPrefExcludeAppsKey` | NSArray | [OpenOffice.org] | Apps to exclude from monitoring |

#### Menu Display

| Key | Type | Default | Description |
|---|---|---|---|
| `CMPrefMaxMenuItemTitleLengthKey` | NSUInteger | 20 | Max chars in menu item title |
| `CMPrefNumberOfItemsPlaceInlineKey` | NSUInteger | 0 | Clips shown at top level |
| `CMPrefNumberOfItemsPlaceInsideFolderKey` | NSUInteger | 10 | Clips per subfolder |
| `CMPrefMenuItemsAreMarkedWithNumbersKey` | BOOL | YES | Prefix items with numbers |
| `CMPrefMenuItemsTitleStartWithZeroKey` | BOOL | NO | Start numbering at 0 |
| `CMPrefAddNumericKeyEquivalentsKey` | BOOL | NO | Cmd+1…0 shortcuts |
| `CMPrefShowLabelsInMenuKey` | BOOL | YES | Show type label in title |
| `CMPrefAddClearHistoryMenuItemKey` | BOOL | YES | Show "Clear History" item |
| `CMPrefShowAlertBeforeClearHistoryKey` | BOOL | YES | Confirm before clearing |
| `CMPrefShowToolTipOnMenuItemKey` | BOOL | YES | Show tooltip on hover |
| `CMPrefMaxLengthOfToolTipKey` | NSUInteger | 200 | Max tooltip length |
| `CMPrefChangeFontSizeKey` | BOOL | NO | Override menu font size |
| `CMPrefHowToChangeFontSizeKey` | NSInteger | 0 | 0=auto (match icon size), 1=manual |
| `CMPrefSelectedFontSizeKey` | NSUInteger | 14 | Manual font size |
| `CMPrefShowImageInTheMenuKey` | BOOL | YES | Show image thumbnails |
| `CMPrefThumbnailWidthKey` | NSUInteger | 100 | Thumbnail width (px) |
| `CMPrefThumbnailHeightKey` | NSUInteger | 32 | Thumbnail height (px) |
| `CMPrefShowIconInTheMenuKey` | BOOL | YES | Show type icon |
| `CMPrefMenuIconSizeKey` | NSUInteger | 16 | Icon size: 16, 32, or 48 |

#### Per-Type Icons

For each type name `T` in `{String, RTF, RTFD, PDF, Filenames, URL, TIFF, PICT}`:
- `"menuIconOfFileTypeTagFor<T>"` — NSInteger: 0=filename extension, 1=HFS type code
- `"menuIconOfFileTypeFor<T>"` — NSString: the extension or 4-char HFS type

#### Actions

| Key | Type | Default | Description |
|---|---|---|---|
| `CMPrefEnableActionKey` | BOOL | YES | Enable action system |
| `CMPrefInvokeActionImmediatelyKey` | BOOL | NO | Skip action menu if only one action |
| `CMPrefContorlClickBehaviorKey` | id | `"popUpActionMenu"` | Ctrl+click behavior |
| `CMPrefShiftClickBehaviorKey` | id | `""` | Shift+click behavior |
| `CMPrefOptionClickBehaviorKey` | id | `""` | Option+click behavior |
| `CMPrefCommandClickBehaviorKey` | id | `""` | Cmd+click behavior |

Behavior values: `""` (no-op), `"popUpActionMenu"` (show action menu), or an action `NSDictionary`.

#### Snippets

| Key | Type | Default | Description |
|---|---|---|---|
| `CMPrefPositionOfSnippetsKey` | NSInteger | `CMPositionOfSnippetsBelowClips` (1) | 0=above, 1=below, 2=none |

#### Updates (Sparkle)

| Key | Type | Default | Description |
|---|---|---|---|
| `CMEnableAutomaticCheckKey` | BOOL | YES | Enable auto-update check |
| `CMEnableAutomaticCheckPreReleaseKey` | BOOL | NO | Use pre-release feed |
| `CMUpdateCheckIntervalKey` | NSInteger | 86400 | Check interval (seconds) |

Feed URLs read from `Info.plist`: `SUFeedURL` and `SUPreReleaseFeedURL`.

#### Hotkeys

| Key | Type | Description |
|---|---|---|
| `CMPrefHotKeysKey` | NSDictionary | Maps identifier → PTKeyCombo plist dict |

---

## Bundled JavaScript Actions

Located in `ClipMenu.app/Contents/Resources/script/action/`. Organised into subdirectories that become folder nodes in the action tree.

### Case
- `lowercase.js` — converts `clipText` to lowercase
- `uppercase.js` — converts `clipText` to uppercase
- `capitalize.js` — capitalizes first letter of each word

### Trim / Collapse
- `trim.js` — removes leading/trailing whitespace
- `collapseSpaces.js` — collapses runs of whitespace to single space

### Transform
- `reverse.js` — reverses character order

### HTML
- `htmlEncode.js` — encodes `&`, `<`, `>`, `"` as HTML entities
- `htmlDecode.js` — decodes HTML entities
- `stripTags.js` — strips HTML tags

### Surround With
Various scripts wrapping text in bracket pairs, quotes, etc. (English and Japanese variants).

### Crypt
- `md5.js` — MD5 hash of text
- `sha1.js` — SHA-1 hash
- `base64Encode.js` — Base64 encode
- `base64Decode.js` — Base64 decode

### Japanese
- `hiraganaToKatakana.js`, `katakanaToHiragana.js`
- `hankakuToZenkaku.js`, `zenkakuToHankaku.js`

### Script Libraries (`script/lib/`)
- `inflection.js` — string inflection (singularize, pluralize, etc.)
- `showdown.js` — Markdown-to-HTML converter
- `fhconvert.js` — file handle conversion utilities

---

## Login Item Management

`Source/NaoAdditions/NMLoginItems.m` wraps `LSSharedFileList` API:
- `+addPathToLoginItems:hide:` — adds the app bundle path to `kLSSharedFileListSessionLoginItems`
- `+removePathFromLoginItems:` — removes it

Called from `AppController._toggleAddingToLoginItems:` which is triggered on preference panel close.

---

## Localization

Two full localisations: `English.lproj/` and `Japanese.lproj/`. Each contains:
- `Localizable.strings`
- `MainMenu.xib`
- `Preferences.xib`
- `InfoPlist.strings`

Key localised strings include all alert messages, menu item titles, and preference labels.

---

## Preferences Window Tabs

`Source/PrefsWindowController` manages a tabbed window with these tabs:

1. **General** — login item, paste command, reorder, history size, autosave, save-on-quit, polling interval, status item, store types, exclude apps list
2. **Menu** — all menu display settings
3. **Icons** — per-type icon file-type code selection and icon size
4. **Actions** — enable toggle, modified-click mappings, invoke-immediately toggle
5. **Shortcuts** — three Shortcut Recorder controls (one per hotkey)
6. **Updates** — Sparkle auto-check, pre-release channel, interval

### Exclude Apps Panel

`openExcludeOptions` opens a sheet. `addToExcludeList` adds the current frontmost app (via `GetFrontProcess` + `ProcessInformationCopyDictionary`) as a dict `{bundleIdentifier, name}` to `CMPrefExcludeAppsKey`.

---

## Notification

`CMPreferencePanelWillCloseNotification` — posted by `PrefsWindowController` when the window closes. `AppController` observes this to sync the login item state (`_toggleLoginItemState`).

---

## Project Structure Summary

```
ClipMenu/
├── Source/
│   ├── AppController.{h,m}          — application delegate, main controller
│   ├── MenuController.{h,m}         — status item, all menus
│   ├── ClipsController.{h,m}        — pasteboard monitoring, history
│   ├── Clip.{h,m}                   — clipboard entry data model
│   ├── ActionController.{h,m}       — JS engine, action tree
│   ├── ActionNode.{h,m}             — action tree node
│   ├── ActionNodeFactory.{h,m}      — builds ActionNode instances
│   ├── ActionFactory.{h,m}          — builds action NSDictionaries
│   ├── BuiltInActionController.{h,m}— built-in action implementations
│   ├── JavaScriptSupport.{h,m}      — ClipMenu.require() JS bridge
│   ├── ScriptableClip.{h,m}         — Clip wrapper exposed to JS
│   ├── SnippetsController.{h,m}     — Core Data snippet store
│   ├── SnippetEditorController.{h,m}— snippet editor window
│   ├── PrefsWindowController.{h,m}  — preferences window
│   ├── CMUtilities.{h,m}            — paste, path helpers, hotKeyMap
│   ├── constants.h                  — all string constants and #defines
│   ├── PTHotKeys/                   — global hotkey library
│   └── NaoAdditions/                — login items, NSString extensions
├── English.lproj/                   — XIBs and localizable strings
├── Japanese.lproj/                  — Japanese localisation
├── resource/
│   └── script/
│       ├── action/                  — bundled JS action scripts
│       └── lib/                     — JS libraries (inflection, showdown, fhconvert)
├── Snippets.xcdatamodel             — Core Data model
├── Info.plist                       — bundle info, Sparkle feed URLs
└── doc/                             — this documentation
```
