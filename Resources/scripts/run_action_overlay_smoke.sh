#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/.build/action-overlay-smoke"
mkdir -p "$OUT"
if [[ $# -lt 2 ]]; then
# Exercise relocation of persisted bundled-script paths.
ditto "$ROOT/Resources/scripts/action" "$OUT/scripts/action"

swiftc \
  -parse-as-library \
  -O \
  -o "$OUT/ActionOverlaySmoke" \
  "$ROOT/Sources/UI/ActionOverlayPresenter.swift" \
  "$ROOT/Sources/Models/ActionNode.swift" \
  "$ROOT/Sources/Models/ClipEntry.swift" \
  "$ROOT/Sources/Infrastructure/StoreEncryption.swift" \
  "$ROOT/Sources/Services/ActionService.swift" \
  "$ROOT/Sources/Infrastructure/PasteService.swift" \
  "$ROOT/Sources/Infrastructure/HistoryErasure.swift" \
  "$ROOT/Sources/Scripting/ScriptEngine.swift" \
  "$ROOT/Sources/Scripting/ScriptableClip.swift" \
  "$ROOT/Resources/scripts/test_action_overlay_host.swift"

# These phases drive AppKit input through the real native tracking loop.
for phase in event-routing event-hover shortcuts mouse keyboard escape outside reopen; do
  ACTION_OVERLAY_SMOKE_PHASE="$phase" "$OUT/ActionOverlaySmoke"
done

echo "[ACTION MENU SMOKE] ALL PASS"
fi

# Optional full-app integration (build ClipMenuTest first). Isolated SwiftData
# fixtures; only the final paste is captured by the existing test harness.
if [[ $# -gt 0 ]]; then
  phases=(mouse keyboard escape status-mouse status-keyboard no-tap-mouse direct-mouse drag-hover shortcuts footer-main footer-history footer-snippets footer-actions status-footer)
  if [[ $# -gt 1 ]]; then phases=("$2"); fi
  for phase in "${phases[@]}"; do
    CLIPMENU_UI_TEST_MODE=1 CLIPMENU_NATIVE_MENU_TEST=1 CLIPMENU_ACTION_SMOKE_PHASE="$phase" \
      "$1/Contents/MacOS/ClipMenuTest" --self-test-action-menu 2>&1 | tee "$OUT/full-$phase.log"
    grep -Fq "[NATIVE ACTION SMOKE] PASS $phase" "$OUT/full-$phase.log"
  done
fi
