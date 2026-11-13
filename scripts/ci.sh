#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v uv >/dev/null || { echo 'FAIL setup: uv not installed'; exit 1; }
uv python install 3.14 || { echo 'FAIL setup: python 3.14'; exit 1; }
if [ -z "${MOJO:-}" ]; then
  uv sync -q || { echo 'FAIL setup: uv sync'; exit 1; }
  MOJO=.venv/bin/mojo
fi
# the oracle is Python 3.14 on every channel (pyproject pins it); MOJO= used to skip uv sync and fall back to python3
PYTHON=$(uv python find 3.14) || { echo 'FAIL setup: python 3.14 not found'; exit 1; }
"$MOJO" --version
mkdir -p .work/t
for t in tests/cases:.work/cases tests/api:.work/t/api examples/quickstart:.work/t/quickstart tests/fuzz_probe:.work/t/fuzz_probe tests/write_probe:.work/t/write_probe; do
  scripts/cap.sh "$MOJO" build -O3 -I src ${MOJO_FLAGS:-} "${t%%:*}.mojo" -o "${t##*:}" > .work/build.err 2>&1 || { echo "FAIL build: ${t%%:*}.mojo"; head -50 .work/build.err; exit 1; }
done
CASES=.work/cases scripts/check.sh | tee .work/gate.txt
MOJO="$MOJO" scripts/mutants.sh | tee .work/mutants.txt
scripts/cap.sh .work/t/api
scripts/cap.sh .work/t/quickstart
# Differential vs CPython: reader (wide dialects, numeric modes, line_num) and writer.
differential() {  # NAME GENERATOR PROBE SEED COUNT
  scripts/cap.sh "$PYTHON" -I "tools/$2" ".work/t/$1" "$4" "$5"
  scripts/cap.sh ".work/t/$3" ".work/t/$1.bin" > ".work/t/$1.got"
  diff -u ".work/t/$1.exp" ".work/t/$1.got" > ".work/t/$1.diff" || { head -20 ".work/t/$1.diff"; echo "FAIL differential $1"; exit 1; }
  # checker self-test: a corrupted expectation must be rejected
  sed '1s/^/x/' ".work/t/$1.exp" | diff -q - ".work/t/$1.got" > /dev/null && { echo "FAIL differential $1: checker accepted a corrupted expectation"; exit 1; }
  echo "PASS differential $1 $5"
}
differential fuzz oracle_fuzz.py fuzz_probe 7 20000
differential wfuzz oracle_write_fuzz.py write_probe 7 20000
echo 'PASS 6/6'
echo 'PASS ci'
