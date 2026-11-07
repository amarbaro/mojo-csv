"""Replays tools/oracle_write_fuzz.py cases through write_all, one hex line (or ERR) per case."""
from csv import Dialect, OwnedField, write_all
from std.sys import argv

comptime HEX = "0123456789abcdef"

def main() raises:
    var buf = open(argv()[1], "r").read_bytes()
    var i = 0
    while i < len(buf):
        var d = Dialect(delimiter=buf[i], quotechar=buf[i + 1], escapechar=buf[i + 2], has_escape=buf[i + 3] == 1,
            doublequote=buf[i + 4] == 1, skipinitialspace=buf[i + 5] == 1, quoting=Int(buf[i + 6]))
        var tl = Int(buf[i + 7])
        i += 8
        var term = List[UInt8]()
        for k in range(tl):
            term.append(buf[i + k])
        d.lineterminator = term^
        i += tl
        var nrows = Int(buf[i]) | (Int(buf[i + 1]) << 8)
        i += 2
        var rows = List[List[OwnedField]]()
        for _ in range(nrows):
            var nf = Int(buf[i])
            i += 1
            var row = List[OwnedField]()
            for _ in range(nf):
                var kind = buf[i]
                var n = Int(buf[i + 1]) | (Int(buf[i + 2]) << 8)
                i += 3
                var data = List[UInt8]()
                for k in range(n):
                    data.append(buf[i + k])
                i += n
                row.append(OwnedField(data^, kind == 0))
            rows.append(row^)
        var out = String()
        try:
            var w = write_all(rows, d)
            for b in w:
                out += HEX[byte=Int(b >> 4)]
                out += HEX[byte=Int(b & 15)]
        except:
            out = "ERR"
        print(out)
