#!/usr/bin/env bash
# Phase 122: where a chain solve goes, on every target.
# Usage: benchmark/run_chain_solve.sh [scale]   (scale multiplies rep counts)
set -euo pipefail
cd "$(dirname "$0")/.."
scale="${1:-1}"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

echo "== VM (JIT) =="
dart run benchmark/chain_solve_bench.dart "$scale"

echo "== AOT (dart compile exe) =="
dart compile exe benchmark/chain_solve_bench.dart -o "$out/bench" >/dev/null
"$out/bench" "$scale"

echo "== dart2js -O4 (node) =="
dart compile js -O4 benchmark/chain_solve_bench.dart -o "$out/bench.js" >/dev/null
node "$out/bench.js" "$scale"

echo "== dart2wasm (node) =="
dart compile wasm benchmark/chain_solve_bench.dart -o "$out/bench.wasm" >/dev/null
node benchmark/wasm_driver.mjs "$out/bench.wasm" "$scale"
