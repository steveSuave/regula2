#!/bin/zsh
# Phase 139 benchmark: what a traced trial costs, and against what —
# the evidence for `TracingFlags.dragStepBudgetWork`.
# Usage: benchmark/run_drag_budget.sh [scale]   (scale multiplies frame counts)
set -e
cd "$(dirname "$0")/.."
scale="${1:-1}"
out=build/bench
mkdir -p "$out"

echo "== VM (JIT) =="
dart run benchmark/drag_budget_bench.dart "$scale"

echo "== AOT (dart compile exe) =="
dart compile exe benchmark/drag_budget_bench.dart -o "$out/drag_budget.exe" >/dev/null
"$out/drag_budget.exe" "$scale"

echo "== dart2js -O4 (node) =="
dart compile js -O4 benchmark/drag_budget_bench.dart -o "$out/drag_budget.js" >/dev/null
node "$out/drag_budget.js" "$scale"

echo "== dart2wasm (node) =="
dart compile wasm benchmark/drag_budget_bench.dart -o "$out/drag_budget.wasm" >/dev/null
node benchmark/wasm_driver.mjs "$out/drag_budget.wasm" "$scale"
