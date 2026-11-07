#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CASES:?FAIL setup: set CASES to the built case runner}"
CHECK_DIR=${CHECK_DIR:-.work/check}
mkdir -p "$CHECK_DIR"
if ! scripts/cap.sh "$CASES" > "$CHECK_DIR/cases.out" 2>&1; then
  head -20 "$CHECK_DIR/cases.out" | cut -c1-400
  echo "FAIL check: case runner"
  exit 1
fi
grep -q '^PASS golden ' "$CHECK_DIR/cases.out" || { echo 'FAIL check: no golden receipt'; exit 1; }
grep -q '^PASS brute 10000$' "$CHECK_DIR/cases.out" || { echo 'FAIL check: no brute receipt'; exit 1; }
grep -q '^PASS cases$' "$CHECK_DIR/cases.out" || { echo 'FAIL check: no final receipt'; exit 1; }
cat "$CHECK_DIR/cases.out"
echo "PASS all"
