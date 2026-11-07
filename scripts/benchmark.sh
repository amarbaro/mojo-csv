#!/usr/bin/env bash
# Interleaved Mojo/CPython rounds per mode: MOJO=path/to/mojo scripts/benchmark.sh (CPU via BENCH_CPU, default 7).
set -euo pipefail
cd "$(dirname "$0")/.."
MOJO=${MOJO:-.venv/bin/mojo}
PYTHON=${PYTHON:-python3}
mkdir -p .work/benchmark
scripts/cap.sh "$MOJO" build -O3 -I src tests/bench.mojo -o .work/benchmark/reader > .work/benchmark/build.txt 2>&1 || { head -50 .work/benchmark/build.txt; echo 'FAIL benchmark: build'; exit 1; }
for mode in stream owned write; do
  : > ".work/benchmark/$mode.txt"
  for round in 1 2 3; do
    { echo "== $mode round $round: Mojo"; scripts/bench-run.sh env BENCH_MODE="$mode" .work/benchmark/reader
      echo "== $mode round $round: CPython"; scripts/bench-run.sh env BENCH_MODE="$mode" "$PYTHON" -I tools/bench_ref.py; } 2>&1 | tee -a ".work/benchmark/$mode.txt"
  done
done
