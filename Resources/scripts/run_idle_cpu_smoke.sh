#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="${1:-}"
if [[ -z "$APP" ]]; then
  echo "Usage: run_idle_cpu_smoke.sh /path/to/clipM.app" >&2
  exit 2
fi
OUT="$ROOT/.build/idle-cpu-smoke"
mkdir -p "$OUT"
swiftc -O -framework AppKit -o "$OUT/IdleCpuSmoke" \
  "$ROOT/Resources/scripts/test_idle_cpu.swift"
"$OUT/IdleCpuSmoke" "$APP"
