#!/bin/zsh
# Phase 101 benchmark: complex arithmetic across compile targets.
# Usage: benchmark/run_all.sh [scale]   (scale multiplies iteration counts)
set -e
cd "$(dirname "$0")/.."
scale="${1:-1}"
out=build/bench
mkdir -p "$out"

echo "== VM (JIT) =="
dart run benchmark/complex_bench.dart "$scale"

echo "== AOT (dart compile exe) =="
dart compile exe benchmark/complex_bench.dart -o "$out/bench.exe" >/dev/null
"$out/bench.exe" "$scale"

echo "== dart2js -O4 (node) =="
dart compile js -O4 benchmark/complex_bench.dart -o "$out/bench.js" >/dev/null
node "$out/bench.js" "$scale"

echo "== dart2wasm (node) =="
dart compile wasm benchmark/complex_bench.dart -o "$out/bench.wasm" >/dev/null
node benchmark/wasm_driver.mjs "$out/bench.wasm" "$scale"
