"""Byte CSV reader/writer. State transitions follow CPython 3.14 Modules/_csv.c."""

comptime QUOTE_MINIMAL = 0
comptime QUOTE_ALL = 1
comptime QUOTE_NONNUMERIC = 2
comptime QUOTE_NONE = 3
comptime QUOTE_STRINGS = 4
comptime QUOTE_NOTNULL = 5
comptime _START_RECORD = 0
comptime _START_FIELD = 1
comptime _ESCAPED_CHAR = 2
comptime _IN_FIELD = 3
comptime _IN_QUOTED_FIELD = 4
comptime _ESCAPE_IN_QUOTED_FIELD = 5
comptime _QUOTE_IN_QUOTED_FIELD = 6
comptime _EAT_CRNL = 7
comptime _AFTER_ESCAPED_CRNL = 8
comptime FIELD_LIMIT = 131072


@always_inline
def _ordinary_end(input: Span[UInt8, _], start: Int, d: Dialect) -> Int:
    var i = start
    while i + 16 <= len(input):
        var block = input.unsafe_ptr().unsafe_offset(i).unsafe_load[width=16, alignment=1]()
        var special = block.eq(SIMD[DType.uint8, 16](d.delimiter)) | block.eq(SIMD[DType.uint8, 16](d.quotechar)) | block.eq(SIMD[DType.uint8, 16](10)) | block.eq(SIMD[DType.uint8, 16](13))
        if d.has_escape:
            special |= block.eq(SIMD[DType.uint8, 16](d.escapechar))
        if special.reduce_or():
            break
        i += 16
    while i < len(input):
        var c = input[i]
        if c == d.delimiter or c == d.quotechar or c == 10 or c == 13 or (d.has_escape and c == d.escapechar):
            break
        i += 1
    return i

struct Dialect(Copyable, Movable):
    var delimiter: UInt8
    var quotechar: UInt8
    var escapechar: UInt8
    var has_escape: Bool
    var doublequote: Bool
    var skipinitialspace: Bool
    var strict: Bool
    var quoting: Int
    var lineterminator: List[UInt8]

    def __init__(out self, delimiter: UInt8 = 44, quotechar: UInt8 = 34, escapechar: UInt8 = 0, has_escape: Bool = False, doublequote: Bool = True, skipinitialspace: Bool = False, strict: Bool = False, quoting: Int = QUOTE_MINIMAL):
        self.delimiter = delimiter
        self.quotechar = quotechar
        self.escapechar = escapechar
        self.has_escape = has_escape or escapechar != 0
        self.doublequote = doublequote
        self.skipinitialspace = skipinitialspace
        self.strict = strict
        self.quoting = quoting
        self.lineterminator = [UInt8(13), UInt8(10)]

    def validate(self) raises:
        if self.quoting < 0 or self.quoting > 5:
            raise Error("bad quoting value")
        var chars = [self.delimiter, self.quotechar, self.escapechar]
        for i in range(3):
            if i == 2 and not self.has_escape:
                continue
            var c = chars[i]
            if c == 10 or c == 13 or (i != 0 and c == 32 and self.skipinitialspace):
                raise Error("bad dialect character")
            for b in self.lineterminator:
                if c == b:
                    raise Error("dialect character occurs in lineterminator")
        if self.delimiter == self.quotechar or (self.has_escape and (self.escapechar == self.delimiter or self.escapechar == self.quotechar)):
            raise Error("dialect characters must be distinct")

    @staticmethod
    def excel() -> Dialect:
        return Dialect()

    @staticmethod
    def excel_tab() -> Dialect:
        return Dialect(delimiter=9)

    @staticmethod
    def unix_dialect() -> Dialect:
        var d = Dialect(quoting=QUOTE_ALL)
        d.lineterminator = [UInt8(10)]
        return d^

struct OwnedField(Copyable, Movable):
    var data: List[UInt8]
    var is_null: Bool

    def __init__(out self, var data: List[UInt8], is_null: Bool = False):
        self.data = data^
        self.is_null = is_null

    def __init__(out self):
        self.data = List[UInt8]()
        self.is_null = False

@fieldwise_init
struct CsvField[origin: Origin](ImplicitlyCopyable):
    var data: Span[UInt8, Self.origin]
    var is_null: Bool

    def to_list(self) -> List[UInt8]:
        return List[UInt8](self.data)

@fieldwise_init
struct _Field(ImplicitlyCopyable):
    var start: Int
    var length: Int
    var owned: Bool
    var is_null: Bool

@fieldwise_init
struct CsvRow[origin: Origin](ImplicitlyCopyable, Sized):
    var _input: Span[UInt8, Self.origin]
    var _scratch: Span[UInt8, Self.origin]
    var _fields: Span[_Field, Self.origin]

    def __len__(self) -> Int:
        return len(self._fields)

    def __getitem__(self, index: Int) -> CsvField[Self.origin]:
        var f = self._fields[index]
        var source = self._scratch if f.owned else self._input
        return CsvField(source[f.start:f.start + f.length], f.is_null)

    def to_list(self) -> List[OwnedField]:
        var result = List[OwnedField](capacity=len(self))
        for i in range(len(self)):
            var f = self[i]
            result.append(OwnedField(f.to_list(), f.is_null))
        return result^

struct Reader[origin: Origin]:
    var dialect: Dialect
    var input: Span[UInt8, Self.origin]
    var state: Int
    var unquoted: Bool
    var scratch: List[UInt8]
    var fields: List[_Field]
    var position: Int
    var line_num: Int
    var field_start: Int
    var field_offset: Int
    var field_len: Int
    var field_owned: Bool
    var _validated: Bool

    def __init__(out self, var dialect: Dialect, input: Span[UInt8, Self.origin]):
        self.dialect = dialect^
        self.input = input
        self.state = _START_RECORD
        self.unquoted = True
        self.scratch = List[UInt8]()
        self.fields = List[_Field]()
        self.position = 0
        self.line_num = 0
        self.field_start = 0
        self.field_offset = 0
        self.field_len = 0
        self.field_owned = False
        self._validated = False

    def _add_char(mut self, c: Int) raises:
        if self.field_len >= FIELD_LIMIT:
            raise Error("field larger than field limit (131072)")
        if not self.field_owned and self.position != self.field_start + self.field_len:
            self.scratch.extend(self.input[self.field_start:self.field_start + self.field_len])
            self.field_owned = True
        if self.field_owned:
            self.scratch.append(UInt8(c))
        self.field_len += 1

    def _save_field(mut self) raises:
        var q = self.dialect.quoting
        var null = self.unquoted and self.field_len == 0 and (q == QUOTE_NOTNULL or q == QUOTE_STRINGS)
        var start = self.field_offset if self.field_owned else self.field_start
        if self.unquoted and self.field_len != 0 and (q == QUOTE_NONNUMERIC or q == QUOTE_STRINGS):
            if self.field_owned:
                if not _is_float_bytes(Span(self.scratch)[start:start + self.field_len]):
                    raise Error("could not convert string to float")
            elif not _is_float_bytes(self.input[start:start + self.field_len]):
                raise Error("could not convert string to float")
        self.fields.append(_Field(start, self.field_len, self.field_owned, null))
        self.field_start = self.position + 1
        self.field_offset = len(self.scratch)
        self.field_len = 0
        self.field_owned = False
        self.unquoted = True

    def _process(mut self, c: Int) raises -> Bool:
        if self.state == _START_RECORD:
            if c == -1:
                return True
            if c == 10 or c == 13:
                self.state = _EAT_CRNL
                return False
            self.state = _START_FIELD
        if self.state == _START_FIELD:
            self.unquoted = True
            if c == -1 or c == 10 or c == 13:
                self._save_field()
                self.state = _START_RECORD if c == -1 else _EAT_CRNL
                return c == -1
            if c == Int(self.dialect.quotechar) and self.dialect.quoting != QUOTE_NONE:
                self.unquoted = False
                self.field_owned = True
                self.state = _IN_QUOTED_FIELD
            elif self.dialect.has_escape and c == Int(self.dialect.escapechar):
                self.state = _ESCAPED_CHAR
            elif c == 32 and self.dialect.skipinitialspace:
                pass
            elif c == Int(self.dialect.delimiter):
                self._save_field()
            else:
                self._add_char(c)
                self.state = _IN_FIELD
            return False
        if self.state == _ESCAPED_CHAR:
            self._add_char(10 if c == -1 else c)
            self.state = _AFTER_ESCAPED_CRNL if c == 10 or c == 13 else _IN_FIELD
            return False
        if self.state == _AFTER_ESCAPED_CRNL and c == -1:
            return False
        if self.state == _IN_FIELD or self.state == _AFTER_ESCAPED_CRNL:
            if c == -1 or c == 10 or c == 13:
                self._save_field()
                self.state = _START_RECORD if c == -1 else _EAT_CRNL
                return c == -1
            if self.dialect.has_escape and c == Int(self.dialect.escapechar):
                self.state = _ESCAPED_CHAR
            elif c == Int(self.dialect.delimiter):
                self._save_field()
                self.state = _START_FIELD
            else:
                self._add_char(c)
            return False
        if self.state == _IN_QUOTED_FIELD:
            if c == -1:
                return False
            if self.dialect.has_escape and c == Int(self.dialect.escapechar):
                self.state = _ESCAPE_IN_QUOTED_FIELD
            elif c == Int(self.dialect.quotechar):
                self.state = _QUOTE_IN_QUOTED_FIELD if self.dialect.doublequote else _IN_FIELD
            else:
                self._add_char(c)
            return False
        if self.state == _ESCAPE_IN_QUOTED_FIELD:
            self._add_char(10 if c == -1 else c)
            self.state = _IN_QUOTED_FIELD
            return False
        if self.state == _QUOTE_IN_QUOTED_FIELD:
            if c == Int(self.dialect.quotechar):
                self._add_char(c)
                self.state = _IN_QUOTED_FIELD
            elif c == Int(self.dialect.delimiter):
                self._save_field()
                self.state = _START_FIELD
            elif c == -1 or c == 10 or c == 13:
                self._save_field()
                self.state = _START_RECORD if c == -1 else _EAT_CRNL
                return c == -1
            elif not self.dialect.strict:
                self._add_char(c)
                self.state = _IN_FIELD
            else:
                raise Error("delimiter expected after quote")
            return False
        if c == -1:
            self.state = _START_RECORD
            return True
        if c != 10 and c != 13:
            raise Error("new-line character seen in unquoted field")
        return False

    def reset(mut self):
        self.position = 0
        self.line_num = 0
        self.state = _START_RECORD
        self.fields.clear()
        self.scratch.clear()
        self._validated = False

    def next(mut self) raises -> Bool:
        if not self._validated:
            self.dialect.validate()
            self._validated = True
        self.fields.clear()
        self.scratch.clear()
        self.state = _START_RECORD
        self.unquoted = True
        self.field_start = self.position
        self.field_offset = 0
        self.field_len = 0
        self.field_owned = False
        while self.position < len(self.input):
            self.line_num += 1
            while self.position < len(self.input):
                if self.state == _IN_FIELD or self.state == _IN_QUOTED_FIELD:
                    var end = _ordinary_end(self.input, self.position, self.dialect)
                    if end > self.position:
                        if self.field_len + end - self.position > FIELD_LIMIT:
                            raise Error("field larger than field limit (131072)")
                        if self.field_owned:
                            self.scratch.extend(self.input[self.position:end])
                        self.field_len += end - self.position
                        self.position = end
                        continue
                var c = Int(self.input[self.position])
                _ = self._process(c)
                self.position += 1
                if c == 13:
                    if self.position < len(self.input) and self.input[self.position] == 10:
                        _ = self._process(10)
                        self.position += 1
                if c == 10 or c == 13:
                    break
            if self._process(-1):
                return True
        if self.field_len != 0 or self.state == _IN_QUOTED_FIELD:
            if self.dialect.strict:
                raise Error("unexpected end of data")
            self._save_field()
            return True
        return False

    def row(ref self) -> CsvRow[ImmOrigin(origin_of(self))]:
        # Bind view types to the reader origin. Tested compilers still accept
        # invalid retention: the documented next/reset/input contract applies.
        return CsvRow(
            Span[UInt8, ImmOrigin(origin_of(self))](unsafe_ptr=self.input.unsafe_ptr().as_imm().unsafe_origin_cast[ImmOrigin(origin_of(self))](), length=len(self.input)),
            Span[UInt8, ImmOrigin(origin_of(self))](unsafe_ptr=self.scratch.unsafe_ptr().as_imm().unsafe_origin_cast[ImmOrigin(origin_of(self))](), length=len(self.scratch)),
            Span[_Field, ImmOrigin(origin_of(self))](unsafe_ptr=self.fields.unsafe_ptr().as_imm().unsafe_origin_cast[ImmOrigin(origin_of(self))](), length=len(self.fields)))

    def read_all(mut self) raises -> List[List[OwnedField]]:
        self.reset()
        var rows = List[List[OwnedField]]()
        while self.next():
            rows.append(self.row().to_list())
        return rows^

def _is_float_bytes(b: Span[UInt8, _]) -> Bool:
    var start = 0
    var end = len(b)
    while start < end and (b[start] == 32 or (b[start] >= 9 and b[start] <= 13)):
        start += 1
    while end > start and (b[end - 1] == 32 or (b[end - 1] >= 9 and b[end - 1] <= 13)):
        end -= 1
    if start < end and (b[start] == 43 or b[start] == 45):
        start += 1
    if end - start == 3 or end - start == 8:
        var word = UInt64(0)
        for i in range(start, end):
            word = (word << 8) | UInt64(b[i] | 32)
        # Packed lowercase ASCII: inf, nan, infinity. No temporary String.
        if word == 0x696e66 or word == 0x6e616e or word == 0x696e66696e697479:
            return True
    var digits = 0
    var exponent_digits = 0
    var dot = False
    var exponent = False
    var i = start
    while i < end:
        var c = b[i]
        if c >= 48 and c <= 57:
            digits += 1
            if exponent:
                exponent_digits += 1
        elif c == 95:
            if i == start or i + 1 == end or b[i - 1] < 48 or b[i - 1] > 57 or b[i + 1] < 48 or b[i + 1] > 57:
                return False
        elif c == 46 and not dot and not exponent:
            dot = True
        elif (c == 101 or c == 69) and not exponent and digits > 0:
            exponent = True
            if i + 1 < end and (b[i + 1] == 43 or b[i + 1] == 45):
                i += 1
        else:
            return False
        i += 1
    return digits > 0 and (not exponent or exponent_digits > 0)

def _special_table(d: Dialect) -> Array[UInt8, 256]:
    # One 256-byte stack table per call replaces per-byte dialect and terminator compares.
    var t = Array[UInt8, 256](fill=0)
    t[Int(d.delimiter)] = 1
    t[Int(d.quotechar)] = 1
    t[10] = 1
    t[13] = 1
    if d.has_escape:
        t[Int(d.escapechar)] = 1
    for b in d.lineterminator:
        t[Int(b)] = 1
    return t^

def write_all(rows: List[List[OwnedField]], dialect: Dialect) raises -> List[UInt8]:
    dialect.validate()
    var special = _special_table(dialect)
    var capacity = 0
    for row in rows:
        capacity += len(dialect.lineterminator) + len(row)
        for index in range(len(row)):
            capacity += len(row[index].data) + 2
    var output = List[UInt8](capacity=capacity)
    for row in rows:
        for index in range(len(row)):
            ref field = row[index]
            if index > 0:
                output.append(dialect.delimiter)
            var quoted = dialect.quoting == QUOTE_ALL or dialect.quoting == QUOTE_NONNUMERIC or ((dialect.quoting == QUOTE_STRINGS or dialect.quoting == QUOTE_NOTNULL) and not field.is_null)
            var length = 0 if field.is_null else len(field.data)
            if length == 0 and dialect.delimiter == 32 and dialect.skipinitialspace:
                if dialect.quoting == QUOTE_NONE or (field.is_null and (dialect.quoting == QUOTE_STRINGS or dialect.quoting == QUOTE_NOTNULL)):
                    raise Error("empty field must be quoted with space delimiter")
                quoted = True
            var plain = True
            for i in range(length):
                var c = field.data[i]
                if special[Int(c)] != 0:
                    plain = False
                if special[Int(c)] != 0 and dialect.quoting != QUOTE_NONE:
                    if c == dialect.quotechar and not dialect.doublequote:
                        pass
                    elif dialect.has_escape and c == dialect.escapechar:
                        pass
                    else:
                        quoted = True
            if len(row) == 1 and length == 0 and not quoted:
                if dialect.quoting == QUOTE_NONE or (field.is_null and (dialect.quoting == QUOTE_STRINGS or dialect.quoting == QUOTE_NOTNULL)):
                    raise Error("single empty field record must be quoted")
                quoted = True
            if quoted:
                output.append(dialect.quotechar)
            if plain:
                output.extend(Span(field.data)[:length])
            for i in range(0 if plain else length):
                var c = field.data[i]
                if special[Int(c)] != 0:
                    if dialect.quoting == QUOTE_NONE or (dialect.has_escape and c == dialect.escapechar) or (c == dialect.quotechar and not dialect.doublequote):
                        if not dialect.has_escape:
                            raise Error("need to escape, but no escapechar set")
                        output.append(dialect.escapechar)
                    elif c == dialect.quotechar:
                        output.append(dialect.quotechar)
                output.append(c)
            if quoted:
                output.append(dialect.quotechar)
        for c in dialect.lineterminator:
            output.append(c)
    return output^
