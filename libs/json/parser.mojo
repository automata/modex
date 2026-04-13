"""Native JSON parser helpers."""

fn _is_ws(b: UInt8) -> Bool:
    return (
        b == UInt8(ord(" "))
        or b == UInt8(ord("\n"))
        or b == UInt8(ord("\r"))
        or b == UInt8(ord("\t"))
    )


fn skip_ws(s: String, start: Int = 0) -> Int:
    var i = start
    var bs = s.as_bytes()
    while i < len(s) and _is_ws(bs[i]):
        i += 1
    return i


fn parse_string_end(s: String, quote_pos: Int) raises -> Int:
    var i = quote_pos + 1
    var bs = s.as_bytes()
    while i < len(s):
        if bs[i] == UInt8(ord("\\")):
            i += 2
            continue
        if bs[i] == UInt8(ord("\"")):
            return i + 1
        i += 1
    raise Error("Unterminated JSON string")


fn parse_literal(s: String, start: Int, literal: String) raises -> Int:
    if start + len(literal) > len(s):
        raise Error("Unexpected end of JSON")
    if String(s[start : start + len(literal)]) != literal:
        raise Error("Invalid JSON literal")
    return start + len(literal)


fn parse_number_end(s: String, start: Int) raises -> Int:
    var i = start
    var bs = s.as_bytes()
    if i < len(s) and bs[i] == UInt8(ord("-")):
        i += 1
    if i >= len(s):
        raise Error("Invalid JSON number")

    if bs[i] == UInt8(ord("0")):
        i += 1
    else:
        if bs[i] < UInt8(ord("1")) or bs[i] > UInt8(ord("9")):
            raise Error("Invalid JSON number")
        while i < len(s) and bs[i] >= UInt8(ord("0")) and bs[i] <= UInt8(ord("9")):
            i += 1

    if i < len(s) and bs[i] == UInt8(ord(".")):
        i += 1
        if i >= len(s) or bs[i] < UInt8(ord("0")) or bs[i] > UInt8(ord("9")):
            raise Error("Invalid JSON number")
        while i < len(s) and bs[i] >= UInt8(ord("0")) and bs[i] <= UInt8(ord("9")):
            i += 1

    if i < len(s) and (bs[i] == UInt8(ord("e")) or bs[i] == UInt8(ord("E"))):
        i += 1
        if i < len(s) and (bs[i] == UInt8(ord("+")) or bs[i] == UInt8(ord("-"))):
            i += 1
        if i >= len(s) or bs[i] < UInt8(ord("0")) or bs[i] > UInt8(ord("9")):
            raise Error("Invalid JSON exponent")
        while i < len(s) and bs[i] >= UInt8(ord("0")) and bs[i] <= UInt8(ord("9")):
            i += 1

    return i


fn find_value_end(s: String, start: Int = 0) raises -> Int:
    var i = skip_ws(s, start)
    if i >= len(s):
        raise Error("Unexpected end of JSON")

    var bs = s.as_bytes()
    var c = bs[i]
    if c == UInt8(ord("\"")):
        return parse_string_end(s, i)
    if c == UInt8(ord("{")):
        i += 1
        i = skip_ws(s, i)
        if i < len(s) and s.as_bytes()[i] == UInt8(ord("}")):
            return i + 1
        while True:
            i = skip_ws(s, i)
            if i >= len(s) or s.as_bytes()[i] != UInt8(ord("\"")):
                raise Error("Expected object key string")
            i = parse_string_end(s, i)
            i = skip_ws(s, i)
            if i >= len(s) or s.as_bytes()[i] != UInt8(ord(":")):
                raise Error("Expected ':' after object key")
            i += 1
            i = find_value_end(s, i)
            i = skip_ws(s, i)
            if i >= len(s):
                raise Error("Unexpected end of object")
            if s.as_bytes()[i] == UInt8(ord("}")):
                return i + 1
            if s.as_bytes()[i] != UInt8(ord(",")):
                raise Error("Expected ',' or '}' in object")
            i += 1
    if c == UInt8(ord("[")):
        i += 1
        i = skip_ws(s, i)
        if i < len(s) and s.as_bytes()[i] == UInt8(ord("]")):
            return i + 1
        while True:
            i = find_value_end(s, i)
            i = skip_ws(s, i)
            if i >= len(s):
                raise Error("Unexpected end of array")
            if s.as_bytes()[i] == UInt8(ord("]")):
                return i + 1
            if s.as_bytes()[i] != UInt8(ord(",")):
                raise Error("Expected ',' or ']' in array")
            i += 1
    if c == UInt8(ord("t")):
        return parse_literal(s, i, "true")
    if c == UInt8(ord("f")):
        return parse_literal(s, i, "false")
    if c == UInt8(ord("n")):
        return parse_literal(s, i, "null")
    if c == UInt8(ord("-")) or (c >= UInt8(ord("0")) and c <= UInt8(ord("9"))):
        return parse_number_end(s, i)
    raise Error("Invalid JSON value")


fn unescape_json_string(quoted: String) raises -> String:
    var s = quoted
    if len(s) >= 2 and s.as_bytes()[0] == UInt8(ord("\"")) and s.as_bytes()[len(s)-1] == UInt8(ord("\"")):
        s = String(s[1 : len(s) - 1])

    var out = String()
    var i = 0
    var bs = s.as_bytes()
    while i < len(s):
        if bs[i] != UInt8(ord("\\")):
            out += chr(Int(bs[i]))
            i += 1
            continue
        i += 1
        if i >= len(s):
            raise Error("Invalid JSON escape")
        var esc = bs[i]
        if esc == UInt8(ord("\"")):
            out += "\""
        elif esc == UInt8(ord("\\")):
            out += "\\"
        elif esc == UInt8(ord("/")):
            out += "/"
        elif esc == UInt8(ord("b")):
            out += chr(8)
        elif esc == UInt8(ord("f")):
            out += chr(12)
        elif esc == UInt8(ord("n")):
            out += "\n"
        elif esc == UInt8(ord("r")):
            out += "\r"
        elif esc == UInt8(ord("t")):
            out += "\t"
        elif esc == UInt8(ord("u")):
            # Minimal \uXXXX support; decode ASCII range, otherwise replace.
            if i + 4 >= len(s):
                raise Error("Invalid unicode escape")
            var value = 0
            for j in range(1, 5):
                value *= 16
                var h = bs[i + j]
                if h >= UInt8(ord("0")) and h <= UInt8(ord("9")):
                    value += Int(h - UInt8(ord("0")))
                elif h >= UInt8(ord("a")) and h <= UInt8(ord("f")):
                    value += 10 + Int(h - UInt8(ord("a")))
                elif h >= UInt8(ord("A")) and h <= UInt8(ord("F")):
                    value += 10 + Int(h - UInt8(ord("A")))
                else:
                    raise Error("Invalid unicode escape")
            if value >= 0 and value <= 0x7F:
                out += chr(value)
            else:
                out += "?"
            i += 4
        else:
            raise Error("Invalid JSON escape")
        i += 1
    return out
