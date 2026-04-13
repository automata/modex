"""Native JSON serializer helpers."""

from collections import List


fn json_escape_string(s: String) -> String:
    var out = String()
    for i in range(len(s)):
        var b = s.as_bytes()[i]
        if b == UInt8(ord('"')):
            out += "\\\""
        elif b == UInt8(ord('\\')):
            out += "\\\\"
        elif b == UInt8(ord('\n')):
            out += "\\n"
        elif b == UInt8(ord('\r')):
            out += "\\r"
        elif b == UInt8(ord('\t')):
            out += "\\t"
        elif b < 32:
            out += "?"
        else:
            out += chr(Int(b))
    return out


fn json_quote(s: String) -> String:
    return "\"" + json_escape_string(s) + "\""


struct JsonObjectBuilder:
    var out: String
    var first: Bool

    fn __init__(out self):
        self.out = "{"
        self.first = True

    fn _sep(mut self):
        if self.first:
            self.first = False
        else:
            self.out += ","

    fn add_string(mut self, key: String, value: String):
        self._sep()
        self.out += json_quote(key) + ":" + json_quote(value)

    fn add_int(mut self, key: String, value: Int):
        self._sep()
        self.out += json_quote(key) + ":" + String(value)

    fn add_bool(mut self, key: String, value: Bool):
        self._sep()
        self.out += json_quote(key) + ":" + ("true" if value else "false")

    fn add_raw(mut self, key: String, raw_json: String):
        self._sep()
        self.out += json_quote(key) + ":" + raw_json

    fn finish(self) -> String:
        return self.out + "}"


struct JsonArrayBuilder:
    var out: String
    var first: Bool

    fn __init__(out self):
        self.out = "["
        self.first = True

    fn _sep(mut self):
        if self.first:
            self.first = False
        else:
            self.out += ","

    fn add_raw(mut self, raw_json: String):
        self._sep()
        self.out += raw_json

    fn add_string(mut self, value: String):
        self._sep()
        self.out += json_quote(value)

    fn finish(self) -> String:
        return self.out + "]"
