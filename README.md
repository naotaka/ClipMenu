# <img src="Assets.xcassets/AppIcon.appiconset/AppIcon-32.png" alt="ClipMenu icon" width="24" /> ClipMenu

ClipMenu is a macOS clipboard manager rebuilt in Swift (SwiftUI + SwiftData).

![ClipMenu Screenshot](screenshot.jpg)

## Installation

- Download installer: [ClipMenu.dmg](dist/ClipMenu.dmg)
- Open the DMG and install `ClipMenu.app`

## What Is Updated From The Original

This repository now reflects a fully modernized implementation of ClipMenu. Major updates include:

- Replaced legacy polling-style clipboard handling with an event-driven clipboard pipeline.
- Adopted Combine-based publishers/observation in the app flow for reactive updates.
- Migrated persistence to SwiftData models and services.
- Completed end-to-end implementation of the Actions menu, including action execution wiring in the modern app.
- Rebuilt the app architecture in Swift with SwiftUI scenes and a generated Xcode project workflow.

## Huge Thanks

A huge thank you to Naotaka Morimoto, the original author of ClipMenu.

ClipMenu has helped many users for years, and this modernization work stands on top of that original design and effort.

## Current Stack

- Language: Swift 5.9+
- Platform: macOS 14+
- Build system: XcodeGen (`project.yml`)
- App type: menu bar app (`LSUIElement`)
- Dependency: `KeyboardShortcuts`

## Build

Prerequisites:

```sh
xcode-select -p
brew install xcodegen
```

Generate project:

```sh
xcodegen generate
```

Build (Debug):

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Debug build \
	CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

For detailed commands and troubleshooting, see `BUILD.md`.

## Repository Cleanup Status

- Legacy Objective-C source and historical release tooling were removed from the repository after migration completion.
- Historical Sparkle/appcast release scripts are no longer part of this project.
- Release and documentation flow is now maintained directly in Markdown docs in this repository.

## Distribution Note

If you distribute derived work:

1. Do not use `ClipMenu` as your product name.
2. Follow the MIT license terms.

## License

ClipMenu is available under the MIT license. See `LICENSE` for details.
