#!/bin/zsh
# Phase 113 benchmark: naive fixed-step tracing cost per drag frame.
# Usage: benchmark/run_tracing.sh [scale]   (scale multiplies frame counts)
set -e
cd "$(dirname "$0")/.."
scale="${1:-1}"
out=build/bench
mkdir -p "$out"

echo "== VM (JIT) =="
dart run benchmark/tracing_bench.dart "$scale"

echo "== AOT (dart compile exe) =="
dart compile exe benchmark/tracing_bench.dart -o "$out/tracing.exe" >/dev/null
"$out/tracing.exe" "$scale"

echo "== dart2js -O4 (node) =="
dart compile js -O4 benchmark/tracing_bench.dart -o "$out/tracing.js" >/dev/null
node "$out/tracing.js" "$scale"

echo "== dart2wasm (node) =="
dart compile wasm benchmark/tracing_bench.dart -o "$out/tracing.wasm" >/dev/null
node benchmark/wasm_driver.mjs "$out/tracing.wasm" "$scale"
