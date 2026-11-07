"""Same materialized/streamed 50 MB input as tools/bench_ref.py."""
from csv import Reader, Dialect, CsvField, OwnedField, write_all
from std.time import perf_counter_ns
from std.sys import size_of
from std.os import getenv


def main() raises:
    var template = "alpha,beta,\"gamma,delta\",\"say \"\"hi\"\"\",012345678901234567890123456789\r\n"
    var records = Int(getenv("BENCH_BYTES", "50000000")) // template.byte_length()
    var mode = getenv("BENCH_MODE", "stream")
    var input = List[UInt8](capacity=records * template.byte_length())
    for _ in range(records):
        for c in template.as_bytes():
            input.append(c)
    var reader = Reader(Dialect.excel(), Span(input))
    var count = 0
    if mode == "write":
        # Writer: materialize outside the timer, then time write_all alone.
        var rows = reader.read_all()
        var wstart = perf_counter_ns()
        var out = write_all(rows, Dialect.excel())
        var wsec = Float64(perf_counter_ns() - wstart) / 1e9
        if len(out) != len(input) or len(rows) != records:
            raise Error("benchmark writer result mismatch")
        print("Mojo write bytes", len(out), "rows", len(rows))
        print("rows:", len(rows))
        print("parse seconds:", wsec)
        print("parse MB/s:", Float64(len(out)) / wsec / 1e6)
        return
    var started = perf_counter_ns()
    if mode == "owned":
        var rows = reader.read_all()
        count = len(rows)
        if count != records or len(rows[0]) != 5 or len(rows[count - 1][2].data) != 11 or len(rows[count - 1][3].data) != 8:
            raise Error("benchmark materialized result mismatch")
    else:
        while reader.next():
            var row = reader.row()
            if len(row) != 5 or len(row[2].data) != 11 or len(row[3].data) != 8:
                raise Error("benchmark streamed result mismatch")
            count += 1
    var elapsed = Float64(perf_counter_ns() - started) / 1e9
    if count != records:
        raise Error("benchmark row count mismatch")
    print("Mojo", mode, "bytes", len(input), "rows", count)
    print("rows:", count)
    print("parse seconds:", elapsed)
    print("parse MB/s:", Float64(len(input)) / elapsed / 1e6)
    print("sizes Dialect", size_of[Dialect](), "Reader", size_of[type_of(reader)](), "CsvField", size_of[CsvField[ImmStaticOrigin]](), "OwnedField", size_of[OwnedField]())
