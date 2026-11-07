#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec scripts/cap.sh /usr/bin/time -f 'wall seconds: %e\npeak KB: %M' taskset -c "${BENCH_CPU:-7}" "$@"
