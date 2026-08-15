#!/usr/bin/env bash
# Phase 117c: one locus sweep of each reported document, on every target.
# The ratio between these rows is the answer to "is this the engine or the
# debug web compiler?" — note that `flutter run -d chrome` is DDC, which
# none of these rows measure and which is slower than all of them.
set -euo pipefail
cd "$(dirname "$0")/.."
reps="${1:-40}"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

echo "== VM (JIT) =="
dart run benchmark/locus_docs_bench.dart "$reps"

echo "== AOT (dart compile exe) =="
dart compile exe benchmark/locus_docs_bench.dart -o "$out/bench" >/dev/null
"$out/bench" "$reps"

echo "== dart2js -O4 (node) =="
dart compile js -O4 benchmark/locus_docs_bench.dart -o "$out/bench.js" >/dev/null
node "$out/bench.js" "$reps"

echo "== dart2wasm (node) =="
dart compile wasm benchmark/locus_docs_bench.dart -o "$out/bench.wasm" >/dev/null
node benchmark/wasm_driver.mjs "$out/bench.wasm" "$reps"
