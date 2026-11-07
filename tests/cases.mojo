from test_golden import replay
from test_brute import run_brute
from test_lifetime import main as check_lifetime
from test_limit import run_limit
from test_dialect import run_dialect


def main() raises:
    replay()
    run_brute()
    check_lifetime()
    run_limit()
    run_dialect()
    print("PASS cases")
