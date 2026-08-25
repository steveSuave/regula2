#!/usr/bin/env bash
# Phase 167: the prover against Newclid's problem corpus.
#
# Informational, like every other benchmark here — it reports a baseline
# and never fails a build. What it is for is the sentence PLAN repeats
# five times: "the corpus is the limiting factor, not the algebra". Every
# later prover phase is kept or deleted on what it moves in this table.
#
# The corpus is not vendored. It is someone else's data, and 300 problems
# do not belong in test/fixtures/, which is v1's permanent save-format
# corpus. Point --corpus at a checkout of
# https://github.com/Newclid/Newclid.
#
# Usage: benchmark/run_corpus.sh [extra args passed through]
#        benchmark/run_corpus.sh --files=examples.txt --verbose
set -uo pipefail
cd "$(dirname "$0")/.."
exec dart run benchmark/corpus_bench.dart "$@"
