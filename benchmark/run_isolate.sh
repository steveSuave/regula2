#!/bin/zsh
# Phase 140 / M-P0: what `Isolate.run` costs. Native only — dart:isolate
# compiles for web and throws at runtime, which is the point.
# Usage: benchmark/run_isolate.sh [scale]
set -e
cd "$(dirname "$0")/.."
scale="${1:-1}"
out=build/bench
mkdir -p "$out"

echo "== VM (JIT) =="
dart run benchmark/isolate_bench.dart "$scale"

echo "== AOT (dart compile exe) =="
dart compile exe benchmark/isolate_bench.dart -o "$out/isolate.exe" >/dev/null
"$out/isolate.exe" "$scale"
