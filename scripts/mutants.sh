#!/usr/bin/env bash
# Each line of tests/mutants.txt is FILE|FROM|TO: one source change the gate must catch.
# A surviving mutant means a blind gate.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .work
MOJO=${MOJO:-.venv/bin/mojo}; killed=0; n=0; bad=0; cur=""
trap '[ -n "$cur" ] && [ -f .work/orig.mojo ] && cp .work/orig.mojo "$cur"' EXIT INT TERM
while IFS='|' read -r f from to; do
  [ -n "$f" ] || continue; n=$((n+1)); cp "$f" .work/orig.mojo; cur=$f
  grep -qF -- "$from" "$f" || { echo "FAIL mutant $n: pattern not found in $f: $from"; exit 1; }
  python3 -c 'import sys;p,a,b=sys.argv[1:];s=open(p).read();open(p,"w").write(s.replace(a,b,1))' "$f" "$from" "$to"
  # a mutant that does not compile proves nothing (2026-11-07: typo mutants `UUIDX` counted as kills)
  if ! scripts/cap.sh "$MOJO" build -I src ${MOJO_FLAGS:-} tests/cases.mojo -o .work/mutant 2>.work/mutant-build.err; then
    echo "INVALID mutant $n (does not compile): $f: $from -> $to"; bad=$((bad+1))
  elif CHECK_DIR=.work/mcheck CASES=.work/mutant scripts/check.sh >/dev/null 2>&1; then
    echo "SURVIVED mutant $n: $f: $from -> $to"
  else killed=$((killed+1)); echo "KILLED mutant $n: $from -> $to"; fi
  cp .work/orig.mojo "$f"; cur=""
done < tests/mutants.txt
echo "mutants: $killed/$n killed, $bad invalid"
[ "$n" -gt 0 ] && [ "$killed" -eq "$n" ] || { echo "FAIL mutants"; exit 1; }
