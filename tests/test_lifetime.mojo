"""Borrowed row retention is invalid; retain owning copies across next()."""
from csv import Reader, Dialect
from test_golden import unhex, hex_bytes, hex_span
from std.testing import assert_equal


def main() raises:
    var input = unhex("612c22622c63220a642c22652c66220a")
    var reader = Reader(Dialect.excel(), Span(input))
    assert_equal(reader.next(), True)
    var held_row = reader.row()
    var saved_row = held_row.to_list()
    var saved_field = held_row[1].to_list()
    assert_equal(hex_span(held_row[1].data), "622c63")
    var capacity = reader.scratch.capacity()
    assert_equal(reader.next(), True)
    # held_row now expires. Access is invalid even when the compiler accepts it.
    # tests/lifetime/held_row.mojo documents that deliberately invalid sequence.
    assert_equal(hex_span(reader.row()[1].data), "652c66")
    assert_equal(hex_bytes(saved_row[1].data), "622c63")
    assert_equal(hex_bytes(saved_field), "622c63")
    assert_equal(reader.scratch.capacity(), capacity)
    reader.reset()
    assert_equal(hex_bytes(saved_field), "622c63")
    print("PASS lifetime: copies survive next/reset; row invalidation documented")
