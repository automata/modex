"""Native JSON parser and serializer."""

from .parser import find_value_end, parse_string_end, skip_ws, unescape_json_string
from .serializer import JsonArrayBuilder, JsonObjectBuilder, json_escape_string, json_quote
from .value import JsonValue


fn parse_json(text: String) raises -> JsonValue:
    var start = skip_ws(text, 0)
    var end = find_value_end(text, start)
    var tail = skip_ws(text, end)
    if tail != len(text):
        raise Error("Trailing data after JSON value")
    return JsonValue(String(text[start:end]))
