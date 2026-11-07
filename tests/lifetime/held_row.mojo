# INVALID EXAMPLE: compiler may accept it. Never run; row expires on next().
from csv import Reader, Dialect

def main() raises:
    var input: List[UInt8] = [UInt8(97), UInt8(10), UInt8(98), UInt8(10)]
    var reader = Reader(Dialect.excel(), Span(input))
    _ = reader.next()
    var row = reader.row()
    _ = reader.next()
    print(row[0].data[0])  # Invalid: row expires on the second next(), regardless of compilation.
