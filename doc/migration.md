# ClipMenu Migration Notes

Migration from the legacy Objective-C app to the Swift/XcodeGen codebase is complete.

## Current Status

- The Swift implementation in `Sources/` is the active and only code path in this repository.
- Legacy Objective-C source and historical release tooling were removed as post-migration cleanup.
- `ClipMenu.xcodeproj` is generated from `project.yml` via XcodeGen.

## Authoritative References

- Behavior and feature expectations: `doc/features.md`
- Build and verification commands: `BUILD.md`
- High-level progress log and migration decisions: `migration_status.md`

## Maintenance Guidance

When implementing new behavior:

1. Use current Swift code in Sources/ as the primary source of truth.
2. Keep migration_status.md updated for structural changes and milestone work.
3. Regenerate and verify builds using xcodegen generate and xcodebuild (see BUILD.md).
