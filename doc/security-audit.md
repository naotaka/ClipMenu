# Security audit — October 6, 2026

Scope: source and release configuration based on commit `68e92b5`, including the changes in this worktree. The audit branch subsequently integrated the 13 commits from master through `69319b3`; the regression suites and unsigned builds were rerun after resolving that merge. This is a source review with targeted regression tests, not a guarantee that the product is invulnerable or an independent penetration-test certification. The real clipboard, saved history and private release keys were not used for testing.

## Publication assessment

The audit found and fixed several concrete privacy and release weaknesses. Saved history and snippets are still **not encrypted by the app**. Do not market them as encrypted or claim that clearing leaves no forensic trace anywhere. The actual signed, notarized distribution and an upgrade from an installed version still need testing before publication. Source compilation alone does not validate those artifacts.

## Findings and changes

| Priority | Finding | Change / status |
| --- | --- | --- |
| High | Confidential and transient pasteboard items could be persisted, retaining passwords after a manager cleared the system clipboard. | Reject the entire copy if any item carries a concealed, transient or supported password-manager marker, before reading its content. Regression tests cover empty markers and concealed later items. This cannot identify unmarked secrets. |
| High | Clear History only deleted model rows; recoverable content could remain in SQLite pages or its write-ahead log. Both UI paths silently swallowed errors, and the current clipboard survived. | Clear the system clipboard, invalidate old captures and delayed script results, blank retained clip models, delete rows, rebuild the live database with VACUUM and truncate the WAL. On macOS 15+, also purge SwiftData's persistent change log. Both menu paths share confirmation and visible failure handling. Snippets and actions are retained. |
| High | History had no application encryption and its directory relied on ordinary filesystem defaults. | Enforce owner-only directory/store permissions (0700/0600), remove extended ACL grants, and reject wrong ownership, symlinks, nonregular store files and hard-linked store files. Encryption remains recommended and unimplemented. Same-user malware is not excluded by POSIX permissions. |
| Medium | A “Save history when quitting” toggle was never implemented and falsely implied control over persistence. | Removed the ineffective setting and explained actual storage behavior in Preferences. History continues to be saved automatically. |
| Medium | Failed activation or changed focus could send a global paste shortcut to a different app. | Check the expected application and clipboard generation, then address the retained process directly. Abort stale/failed writes. Live signed-app paste integration remains to be checked. |
| Medium | Exclusion UI tried to add the current foreground app while its own Preferences window was foreground. | Use an application chooser. Exclusions use observed foreground identity and advisory source metadata; polling cannot authenticate the producer or guarantee attribution after a rapid app switch. |
| Medium | JavaScript contexts persisted across actions, retaining old clipboard strings and poisoned globals/prototypes. Library paths and user-script mutation paths allowed escapes. | Use a fresh context per action; constrain relative library paths and resolved descendants; reject root deletion and symlink escapes; bound source and result sizes. Clipboard text is passed as a value, not interpolated into executable source. |
| Medium | Oversized images/data and unrestricted XML could consume excessive resources. | Bound clipboard representations, item counts and image dimensions before image decoding. Bound XML bytes, nesting and elements; strip only Core Data's fixed built-in DTD declaration and reject other DTD/entity declarations. Parse a private snapshot, and export atomically with private permissions. |
| High (release) | Package requirements and packaging fallback permitted older Sparkle tools; unnotarized publishing and ignored Gatekeeper failures were possible. | Pin Sparkle 2.10.0 and KeyboardShortcuts 2.4.0, use the resolved Sparkle artifact, remove fallback downloads, fail publication on validation errors, and independently verify the update archive against the app's embedded public key. CI narrows signing-secret exposure and cleans credentials. |
| High (release) | Custom Sparkle Info.plist build settings were absent from the actual built app, including its public key/feed settings. | Generate an explicit input plist with the public key, HTTPS feed and a Boolean signed-feed and pre-extraction verification requirements, and verify the built plist. |
| Low | Extra Apple Events entitlement and permissive handling of network-provided store URLs. | Remove unused Apple Events capability. Restrict App Store response matching and links to the expected bundle and Apple store hosts/schemes. |

## What Clear History does and cannot promise

Successful clearing removes clipboard contents from the live application database and its WAL, empties the system clipboard and prevents previously queued captures or script transformations from repopulating the cleared history. Database or journal cleanup failures are reported rather than silently treated as success. Test fixtures check for the old string's UTF-8 and UTF-16 bytes in the live files, verify empty history after reopening, preserve snippets/actions and exercise saving new history afterwards.

This is not physical secure erasure of an SSD. APFS snapshots, Time Machine or other backups, swap/crash dumps, clipboard managers, receiving apps, and explicitly exported or older legacy archives can have independent copies. The app cannot delete those. On macOS 14, the SwiftData change-log deletion API is unavailable: framework change metadata may remain even though clip contents and deleted database pages are removed. A failure during cleanup requires retrying Clear History. macOS 14 runtime behavior has not been exercised on this machine.

These limits follow the distinction in SQLite's [VACUUM documentation](https://www.sqlite.org/lang_vacuum.html) and [WAL documentation](https://www.sqlite.org/wal.html). The implementation uses supported SQLite maintenance commands; it does not edit Core Data's internal tables directly.

## Encryption recommendation

Enable encryption by default before making strong claims about confidential saved history. Use authenticated encryption such as CryptoKit AES-GCM and a random history-specific key protected by macOS Keychain. Keep snippets under a separate key if Clear History must preserve them. Encrypt every clipboard representation and sensitive metadata; fail closed when the key is inaccessible, with no plaintext fallback. Migration, crash recovery and both signing channels need explicit tests.

Clear History should discard the previous history key and create a new one for future captures, as well as remove the encrypted files. This reduces exposure from leftover encrypted history, but does not erase old plaintext backups or copies of keys made elsewhere. Apple's [Keychain accessibility documentation](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly) describes an unlocked-device, nonmigrating key policy. Encryption does not stop an attacker who can already read the running app's memory or the system clipboard.

## Other remaining limits

- Custom JavaScript actions run in-process. They have no exposed network or shell API, but can loop or allocate until the app stops responding; size limits are not a CPU or memory sandbox. Only trusted actions should be installed. Process isolation and enforceable execution budgets remain future work.
- ImageIO/AppKit/Core Data/JavaScriptCore are OS parser attack surfaces; this review is not a parser fuzzing campaign. Install current macOS security updates.
- File containment checks mitigate straightforward escapes, but do not create a boundary against a malicious process with the same user's full filesystem access racing file operations.
- The direct build is unsandboxed; the App Store target enables App Sandbox. Accessibility permission allows synthetic paste. The reviewed source contains no clipboard upload, telemetry or cloud history sync path; network use is for updates and explicit links. This is a source finding, not packet-capture verification.
- Existing history may already contain secrets captured by earlier versions. The new filter cannot retroactively identify them; users can clear existing history.

## Verification

Merge integration preserves the welcome flow and consent prompt while capturing the intended paste target and clipboard generation before the prompt can change focus. The direct target uses `Resources/DirectDistributionInfo.plist`, version 0.9 and bundle ID `org.unitedvisions.ClipM`, with both Sparkle verification policies retained. Nine release tag/version guard cases cover the two-component version, three-component versions and invalid inputs. The App Store package was also built in a separate derived-data folder and checked for the absence of Sparkle; switching targets in a shared products folder leaves stale frameworks. `BUILD.md` now uses separate channel folders. UI interaction and signed-distribution checks remain outstanding.

- Clipboard security suite: 43 checks using a private named pasteboard and in-memory history.
- Script/import security suite: 29 checks covering context isolation, injection, path escapes, XML limits and export/import round trips.
- Existing core services suite: 23 checks for clipboard round trips, deduplication and script failures.
- Storage suite: synthetic disk-backed SwiftData persistence, permissions/ACLs, migration, symlink/hard-link rejection, clear/reopen, preserved snippets/actions, stale selection/capture rejection, byte absence in live database files and error propagation.
- Release gates: 10 synthetic-key signature/publishing checks.
- XcodeGen generation, an unsigned direct Debug build, and unsigned Release builds of direct and App Store targets. No app was launched against real user data; no release was published.
- Pattern scan of 806 reachable Git-history blobs found no matches for private-key headers, common GitHub tokens, AWS access-key IDs, Slack tokens or OpenAI-style tokens. This is a limited format scan, not proof that the repository never contained a secret.

Sparkle's published [installer path advisory](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-3x7w-j75x-ppq5) affects versions through 2.9.5 and identifies 2.9.6 as patched; the locked 2.10.0 is newer. The broader [Sparkle advisory list](https://github.com/sparkle-project/Sparkle/security/advisories) and [KeyboardShortcuts security page](https://github.com/sindresorhus/KeyboardShortcuts/security) were reviewed. Absence of a published advisory is not a guarantee of safety. Confidential pasteboard handling follows the [NSPasteboard conventions](https://nspasteboard.org/).
