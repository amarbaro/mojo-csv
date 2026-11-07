from csv import Reader, Dialect, write_all, OwnedField


def main() raises:
    var input = List[UInt8]()
    for c in "alpha,\"beta,gamma\"\nnext,row\n".as_bytes():
        input.append(c)
    var reader = Reader(Dialect.excel(), Span(input))
    var saved = List[List[OwnedField]]()
    while reader.next():
        var row = reader.row()
        print("fields", len(row))
        saved.append(row.to_list())
    var output = write_all(saved, Dialect.excel())
    if len(saved) != 2 or len(output) != len(input) + 2:
        raise Error("quickstart failed")
    print("rows", len(saved), "written bytes", len(output))
