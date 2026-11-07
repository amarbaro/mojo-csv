from csv import Reader, Dialect
from std.sys import argv

comptime HEX = "0123456789abcdef"

def run_case(d: Dialect, data: Span[UInt8, _]) -> String:
    var out = String()
    try:
        var reader = Reader(d.copy(), data)
        var first = True
        while reader.next():
            if not first:
                out += "|"
            first = False
            out += String(reader.line_num) + ":"
            var row = reader.row()
            for i in range(len(row)):
                if i > 0:
                    out += ","
                var f = row[i]
                if f.is_null:
                    out += "N"
                    continue
                out += "h"
                for b in f.data:
                    out += HEX[byte=Int(b >> 4)]
                    out += HEX[byte=Int(b & 15)]
        return out
    except:
        return "ERR"

def main() raises:
    var buf = open(argv()[1], "r").read_bytes()
    var i = 0
    while i < len(buf):
        var n = Int(buf[i + 8]) | (Int(buf[i + 9]) << 8) | (Int(buf[i + 10]) << 16) | (Int(buf[i + 11]) << 24)
        var d = Dialect(delimiter=buf[i], quotechar=buf[i + 1], escapechar=buf[i + 2],
            has_escape=buf[i + 3] == 1, doublequote=buf[i + 4] == 1, skipinitialspace=buf[i + 5] == 1,
            strict=buf[i + 6] == 1, quoting=Int(buf[i + 7]))
        print(run_case(d, Span(buf)[i + 12 : i + 12 + n]))
        i += 12 + n
