#!/bin/zsh
# Phase 140 / M-P0: cooperative chunking vs the straight-line fixpoint.
# Usage: benchmark/run_threading.sh [scale]   (scale multiplies step budgets)
set -e
cd "$(dirname "$0")/.."
scale="${1:-1}"
out=build/bench
mkdir -p "$out"

echo "== VM (JIT) =="
dart run benchmark/threading_bench.dart "$scale"

echo "== AOT (dart compile exe) =="
dart compile exe benchmark/threading_bench.dart -o "$out/threading.exe" >/dev/null
"$out/threading.exe" "$scale"

echo "== dart2js -O4 (node) =="
dart compile js -O4 benchmark/threading_bench.dart -o "$out/threading.js" >/dev/null
node "$out/threading.js" "$scale"

echo "== dart2wasm (node) =="
dart compile wasm benchmark/threading_bench.dart -o "$out/threading.wasm" >/dev/null
node benchmark/wasm_driver.mjs "$out/threading.wasm" "$scale"
