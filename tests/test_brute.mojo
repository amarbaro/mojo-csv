"""Independent minimal-dialect scanner versus the production state machine."""
from csv import Reader, Dialect
from test_golden import unhex, hex_bytes, encode_rows


def brute(input: List[UInt8]) -> String:
    var rows = String()
    var fields = String()
    var field = List[UInt8]()
    var quoted = False
    var start = True
    var active = False
    var i = 0
    while i < len(input):
        var c = input[i]
        if quoted:
            if c == 34:
                if i + 1 < len(input) and input[i + 1] == 34:
                    field.append(34)
                    i += 1
                else:
                    quoted = False
            else:
                field.append(c)
        elif c == 34 and start:
            quoted = True
            active = True
            start = False
        elif c == 44 or c == 10 or c == 13:
            if c == 44 or active:
                if fields.byte_length() > 0:
                    fields += ","
                fields += "s" + hex_bytes(field)
            if c != 44:
                if rows.byte_length() > 0:
                    rows += "/"
                rows += "~" if not active else fields
                fields = String()
                active = False
                if c == 13 and i + 1 < len(input) and input[i + 1] == 10:
                    i += 1
            else:
                active = True
            field.clear()
            start = True
        else:
            field.append(c)
            active = True
            start = False
        i += 1
    if active:
        if rows.byte_length() > 0:
            rows += "/"
        if fields.byte_length() > 0:
            fields += ","
        rows += fields + "s" + hex_bytes(field)
    return rows^


def next_random(mut seed: UInt32) -> Int:
    seed = seed * 1664525 + 1013904223
    return Int(seed >> 8)


def run_brute() raises:
    var seed = UInt32(0xC5C1)
    var alphabet = unhex("61302c225c0a0d0080ff")
    for trial in range(10000):
        var input = List[UInt8]()
        var records = 1 + next_random(seed) % 4
        for record in range(records):
            var fields = 1 + next_random(seed) % 5
            for column in range(fields):
                if column > 0:
                    input.append(44)
                var quote = next_random(seed) % 2 == 0
                if quote:
                    input.append(34)
                var length = next_random(seed) % 10
                for _ in range(length):
                    var c = alphabet[next_random(seed) % len(alphabet)]
                    if not quote and (c == 44 or c == 34 or c == 10 or c == 13):
                        c = 97
                    input.append(c)
                    if quote and c == 34:
                        input.append(c)
                if quote:
                    input.append(34)
            if record + 1 < records or next_random(seed) % 2 == 0:
                if next_random(seed) % 2 == 0:
                    input.append(13)
                input.append(10)
        var reader = Reader(Dialect.excel(), Span(input))
        var rows = reader.read_all()
        var actual = encode_rows(rows)
        var expected = brute(input)
        if actual != expected:
            print("FAIL brute", trial, hex_bytes(input), expected, actual)
            raise Error("independent oracle mismatch")
    print("PASS brute 10000")


def main() raises:
    run_brute()
