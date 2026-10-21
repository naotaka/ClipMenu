#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/.build/clipboard-security-smoke"
mkdir -p "$OUT/ModuleCache"
swiftc -parse-as-library -O -module-cache-path "$OUT/ModuleCache" -o "$OUT/ClipboardSecuritySmoke" \
  "$ROOT"/Sources/Models/*.swift \
  "$ROOT/Sources/Settings/ClipMenuSettings.swift" \
  "$ROOT/Sources/Infrastructure/ClipboardMonitor.swift" \
  "$ROOT/Sources/Infrastructure/AppExclusionService.swift" \
  "$ROOT/Sources/Infrastructure/PasteService.swift" \
  "$ROOT/Sources/Infrastructure/StoreEncryption.swift" \
  "$ROOT/Sources/Infrastructure/HistoryErasure.swift" \
  "$ROOT/Sources/Services/ClipsService.swift" \
  "$ROOT/Resources/scripts/test_clipboard_security.swift"
"$OUT/ClipboardSecuritySmoke"
