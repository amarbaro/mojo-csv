#!/usr/bin/env bash
# Precompile the package and run the tests with a nightly toolchain: MOJO=path/to/nightly/mojo scripts/nightly.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${MOJO:?FAIL setup: set MOJO to a nightly mojo binary}"
mkdir -p .work/nightly
"$MOJO" --version
scripts/cap.sh "$MOJO" precompile -I src src/csv -o .work/nightly/csv.mojoc
for test in tests/cases.mojo tests/api.mojo examples/quickstart.mojo; do
  name=$(basename "$test" .mojo)
  scripts/cap.sh "$MOJO" build -O3 -I src -I tests "$test" -o ".work/nightly/$name" > ".work/nightly/$name-build.txt" 2>&1 || { head -50 ".work/nightly/$name-build.txt"; echo "FAIL nightly: $test"; exit 1; }
  scripts/cap.sh ".work/nightly/$name"
done
echo 'PASS nightly'
