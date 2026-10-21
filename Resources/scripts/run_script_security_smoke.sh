#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/.build/script-security-smoke"
mkdir -p "$OUT"
swiftc -parse-as-library -O -o "$OUT/ScriptSecuritySmoke" \
  "$ROOT"/Sources/Models/*.swift \
  "$ROOT/Sources/Infrastructure/PasteService.swift" \
  "$ROOT/Sources/Infrastructure/StoreEncryption.swift" \
  "$ROOT/Sources/Infrastructure/HistoryErasure.swift" \
  "$ROOT/Sources/Services/ActionService.swift" \
  "$ROOT/Sources/Services/UserActionScriptsStore.swift" \
  "$ROOT/Sources/Scripting/ScriptEngine.swift" \
  "$ROOT/Sources/Scripting/ScriptableClip.swift" \
  "$ROOT/Sources/Migration/LegacyMigration.swift" \
  "$ROOT/Resources/scripts/test_script_security.swift"
"$OUT/ScriptSecuritySmoke"
