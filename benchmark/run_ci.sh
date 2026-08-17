#!/usr/bin/env bash
# Phase 122: the benchmark suite as one informational run.
#
# Deliberately VM-only and dependency-free, so it costs a minute and needs
# no node or wasm toolchain. It is *informational*: a shared CI runner's
# absolute timings are not the number the 8 ms drag budget is about, so
# this script does not fail on a slow one — it reports, and the numbers
# that decide anything get taken locally with the per-target scripts:
#
#   benchmark/run_tracing.sh       the drag-frame gate, four targets
#   benchmark/run_chain_solve.sh   where a chain solve goes, four targets
#   benchmark/run_locus_docs.sh    the two reported documents, four targets
#   benchmark/run_all.sh           Phase 101 complex throughput, boxed vs SoA
#
# What it *is* good for is catching a change that moves a number by an
# order of magnitude, and having the trend in the log of every push.
#
# Usage: benchmark/run_ci.sh
set -uo pipefail
cd "$(dirname "$0")/.."

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
status=0

emit() {
  printf '%s\n' "$1"
  printf '%s\n' "$1" >>"$summary"
}

emit '## Benchmarks (informational, VM only)'
emit ''

for bench in tracing_bench chain_solve_bench locus_docs_bench; do
  emit "### ${bench}"
  emit '```'
  if output="$(dart run "benchmark/${bench}.dart" 2>&1)"; then
    emit "$output"
  else
    # A benchmark that fails is worth seeing, and worth not failing the
    # build over — including the drag gate, which throws when exceeded.
    status=1
    emit "$output"
    emit ''
    emit "(exited non-zero — see above; not failing the job)"
  fi
  emit '```'
  emit ''
done

if [ "$status" -ne 0 ]; then
  emit '> One or more benchmarks exited non-zero. On a shared runner that is'
  emit '> usually the machine, not the code — reproduce locally with the'
  emit '> per-target scripts before believing it.'
fi

exit 0
