#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/.build/storage-security-smoke"
mkdir -p "$OUT"
swiftc -parse-as-library -O -o "$OUT/StorageSecuritySmoke" \
  "$ROOT"/Sources/Models/*.swift \
  "$ROOT/Sources/Infrastructure/ClipStoreLocation.swift" \
  "$ROOT/Sources/Infrastructure/StoreEncryption.swift" \
  "$ROOT/Sources/Infrastructure/HistoryErasure.swift" \
  "$ROOT/Sources/Settings/ClipMenuSettings.swift" \
  "$ROOT/Sources/Infrastructure/ClipboardMonitor.swift" \
  "$ROOT/Sources/Infrastructure/AppExclusionService.swift" \
  "$ROOT/Sources/Infrastructure/PasteService.swift" \
  "$ROOT/Sources/Services/ClipsService.swift" \
  "$ROOT/Resources/scripts/test_storage_security.swift"
"$OUT/StorageSecuritySmoke"
