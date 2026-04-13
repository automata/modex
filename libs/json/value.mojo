"""JSON value view over raw source text."""

from .parser import find_value_end, parse_string_end, skip_ws, unescape_json_string


struct JsonValue(Copyable):
    var raw: String
    var exists: Bool

    fn __init__(out self):
        self.raw = ""
        self.exists = False

    fn __init__(out self, raw: String, exists: Bool = True):
        self.raw = String(_trim_ws(raw))
        self.exists = exists

    fn is_missing(self) -> Bool:
        return not self.exists

    fn kind(self) -> String:
        if not self.exists or len(self.raw) == 0:
            return "missing"
        var c = self.raw.as_bytes()[0]
        if c == UInt8(ord("{")):
            return "object"
        if c == UInt8(ord("[")):
            return "array"
        if c == UInt8(ord("\"")):
            return "string"
        if c == UInt8(ord("t")) or c == UInt8(ord("f")):
            return "bool"
        if c == UInt8(ord("n")):
            return "null"
        return "number"

    fn as_string(self) raises -> String:
        if self.kind() != "string":
            raise Error("JSON value is not a string")
        return unescape_json_string(self.raw)

    fn as_int(self) raises -> Int:
        if self.kind() != "number":
            raise Error("JSON value is not a number")
        var s = self.raw
        var negative = False
        var i = 0
        if len(s) > 0 and s.as_bytes()[0] == UInt8(ord("-")):
            negative = True
            i = 1
        var value = 0
        while i < len(s):
            var b = s.as_bytes()[i]
            if b < UInt8(ord("0")) or b > UInt8(ord("9")):
                break
            value = value * 10 + Int(b - UInt8(ord("0")))
            i += 1
        return -value if negative else value

    fn as_bool(self) raises -> Bool:
        if self.raw == "true":
            return True
        if self.raw == "false":
            return False
        raise Error("JSON value is not a bool")

    fn is_null(self) -> Bool:
        return self.exists and self.raw == "null"

    fn get(self, key: String) raises -> JsonValue:
        if self.kind() != "object":
            return JsonValue()
        var s = self.raw
        var i = skip_ws(s, 1)
        if i < len(s) and s.as_bytes()[i] == UInt8(ord("}")):
            return JsonValue()
        while i < len(s):
            i = skip_ws(s, i)
            if i >= len(s) or s.as_bytes()[i] != UInt8(ord("\"")):
                return JsonValue()
            var key_end = parse_string_end(s, i)
            var raw_key = String(s[i:key_end])
            var parsed_key = unescape_json_string(raw_key)
            i = skip_ws(s, key_end)
            if i >= len(s) or s.as_bytes()[i] != UInt8(ord(":")):
                return JsonValue()
            i += 1
            var value_start = skip_ws(s, i)
            var value_end = find_value_end(s, value_start)
            if parsed_key == key:
                return JsonValue(String(s[value_start:value_end]))
            i = skip_ws(s, value_end)
            if i < len(s) and s.as_bytes()[i] == UInt8(ord(",")):
                i += 1
                continue
            break
        return JsonValue()

    fn item(self, index: Int) raises -> JsonValue:
        if self.kind() != "array":
            return JsonValue()
        var s = self.raw
        var i = skip_ws(s, 1)
        var current = 0
        if i < len(s) and s.as_bytes()[i] == UInt8(ord("]")):
            return JsonValue()
        while i < len(s):
            var value_start = skip_ws(s, i)
            var value_end = find_value_end(s, value_start)
            if current == index:
                return JsonValue(String(s[value_start:value_end]))
            current += 1
            i = skip_ws(s, value_end)
            if i < len(s) and s.as_bytes()[i] == UInt8(ord(",")):
                i += 1
                continue
            break
        return JsonValue()

    fn len(self) raises -> Int:
        if self.kind() == "array":
            var s = self.raw
            var i = skip_ws(s, 1)
            if i < len(s) and s.as_bytes()[i] == UInt8(ord("]")):
                return 0
            var count = 0
            while i < len(s):
                i = find_value_end(s, skip_ws(s, i))
                count += 1
                i = skip_ws(s, i)
                if i < len(s) and s.as_bytes()[i] == UInt8(ord(",")):
                    i += 1
                    continue
                break
            return count
        if self.kind() == "object":
            var s = self.raw
            var i = skip_ws(s, 1)
            if i < len(s) and s.as_bytes()[i] == UInt8(ord("}")):
                return 0
            var count = 0
            while i < len(s):
                i = skip_ws(s, i)
                if i >= len(s) or s.as_bytes()[i] != UInt8(ord("\"")):
                    break
                i = parse_string_end(s, i)
                i = skip_ws(s, i)
                if i >= len(s) or s.as_bytes()[i] != UInt8(ord(":")):
                    break
                i += 1
                i = find_value_end(s, skip_ws(s, i))
                count += 1
                i = skip_ws(s, i)
                if i < len(s) and s.as_bytes()[i] == UInt8(ord(",")):
                    i += 1
                    continue
                break
            return count
        raise Error("len() only valid for arrays/objects")


fn _trim_ws(s: String) -> String:
    var start = 0
    var stop = len(s)
    var bs = s.as_bytes()
    while start < stop and (
        bs[start] == UInt8(ord(" "))
        or bs[start] == UInt8(ord("\n"))
        or bs[start] == UInt8(ord("\r"))
        or bs[start] == UInt8(ord("\t"))
    ):
        start += 1
    while stop > start and (
        bs[stop - 1] == UInt8(ord(" "))
        or bs[stop - 1] == UInt8(ord("\n"))
        or bs[stop - 1] == UInt8(ord("\r"))
        or bs[stop - 1] == UInt8(ord("\t"))
    ):
        stop -= 1
    return String(s[start:stop])
