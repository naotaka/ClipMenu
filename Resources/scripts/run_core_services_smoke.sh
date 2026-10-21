#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/.build/core-services-smoke"
mkdir -p "$OUT"
swiftc -parse-as-library -O -o "$OUT/CoreServicesSmoke" \
  "$ROOT"/Sources/Models/*.swift \
  "$ROOT/Sources/Settings/ClipMenuSettings.swift" \
  "$ROOT/Sources/Infrastructure/ClipboardMonitor.swift" \
  "$ROOT/Sources/Infrastructure/AppExclusionService.swift" \
  "$ROOT/Sources/Infrastructure/PasteService.swift" \
  "$ROOT/Sources/Infrastructure/StoreEncryption.swift" \
  "$ROOT/Sources/Infrastructure/HistoryErasure.swift" \
  "$ROOT/Sources/Services/ClipsService.swift" \
  "$ROOT/Sources/Scripting/ScriptEngine.swift" \
  "$ROOT/Sources/Scripting/ScriptableClip.swift" \
  "$ROOT/Resources/scripts/test_core_services.swift"
"$OUT/CoreServicesSmoke"
