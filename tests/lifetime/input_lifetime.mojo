# INVALID EXAMPLE: input must remain unchanged and outlive the reader.
from csv import Reader, Dialect

def main() raises:
    var input: List[UInt8] = [UInt8(97), UInt8(10)]
    var reader = Reader(Dialect.excel(), Span(input))
    input.clear()
    print(reader.next())  # Invalid: input was mutated while the reader retained its view.
