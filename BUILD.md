# Build And Release Guide

This repository contains the active Swift/XcodeGen ClipMenu project.

## Prerequisites

```sh
xcode-select -p
brew install xcodegen
```

## Generate Project

Run whenever `project.yml` changes:

```sh
xcodegen generate
```

## Build (Debug)

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Build (Release)

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Release build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Run From Xcode

1. Open `ClipMenu.xcodeproj`.
2. Select scheme `ClipMenu`.
3. Run with `Debug` configuration.

ClipMenu is a menu bar app (`LSUIElement = YES`), so it does not appear in the Dock while running.

## Accessibility Note

Paste simulation uses CGEvent and requires Accessibility permission:

- System Settings -> Privacy & Security -> Accessibility

## Release Direction

- Legacy Sparkle/appcast release scripts were removed during repository cleanup.
- Packaging/notarization should be implemented through a modern, explicit archive/export pipeline when needed.

## Troubleshooting

`xcodegen: command not found`

```sh
brew install xcodegen
```

Code signing errors in local/CI builds

- Use `CODE_SIGN_IDENTITY=""`
- Use `CODE_SIGNING_REQUIRED=NO`
- Use `CODE_SIGNING_ALLOWED=NO`
