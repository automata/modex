"""HTTP response parsing."""

from collections import Dict


struct HttpResponse(Movable):
    """Parsed HTTP/1.1 response."""

    var status_code: Int
    var status_text: String
    var headers: Dict[String, String]
    var body: String
    var raw: String

    fn __init__(out self):
        self.status_code = 0
        self.status_text = ""
        self.headers = Dict[String, String]()
        self.body = ""
        self.raw = ""

    fn __init__(out self, *, deinit take: Self):
        self.status_code = take.status_code
        self.status_text = take.status_text^
        self.headers = take.headers^
        self.body = take.body^
        self.raw = take.raw^

    fn header(self, key: String, default: String = "") -> String:
        """Get header value (case-sensitive). Returns default if missing."""
        try:
            return self.headers[key]
        except:
            return default


fn parse_response(raw: String) raises -> HttpResponse:
    """Parse raw HTTP response into HttpResponse."""
    var resp = HttpResponse()
    resp.raw = raw

    # Find header/body separator "\r\n\r\n"
    var header_end = raw.find("\r\n\r\n")
    if header_end < 0:
        raise Error("Malformed HTTP response: no header/body separator")

    var header_section = String(raw[:header_end])
    resp.body = String(raw[header_end + 4 :])

    _parse_head_into_resp(header_section, resp)

    # Decode chunked transfer encoding transparently.
    var transfer_encoding = get_header_ci(resp, "Transfer-Encoding")
    if len(resp.body) > 0 and _contains_ascii_ci(transfer_encoding, "chunked"):
        resp.body = _decode_chunked_body(resp.body)

    return resp^


fn parse_response_head(header_section: String) raises -> HttpResponse:
    """Parse only status line + headers, without a body."""
    var resp = HttpResponse()
    resp.raw = header_section
    _parse_head_into_resp(header_section, resp)
    return resp^


fn _parse_head_into_resp(header_section: String, mut resp: HttpResponse):
    """Parse response status line and headers into resp."""
    var pos = 0
    var first_line = True

    while pos < len(header_section):
        var next_crlf = header_section.find("\r\n", pos)
        var line: String
        if next_crlf < 0:
            line = String(header_section[pos:])
            pos = len(header_section)
        else:
            line = String(header_section[pos:next_crlf])
            pos = next_crlf + 2

        if len(line) == 0:
            continue

        if first_line:
            _parse_status_line(line, resp)
            first_line = False
        else:
            _parse_header_line(line, resp)


fn _parse_status_line(line: String, mut resp: HttpResponse):
    """Parse 'HTTP/1.1 200 OK' into status_code and status_text."""
    var sp1 = line.find(" ")
    if sp1 < 0:
        return

    var rest = String(line[sp1 + 1 :])
    var sp2 = rest.find(" ")

    if sp2 < 0:
        try:
            resp.status_code = Int(rest)
        except:
            pass
        return

    try:
        resp.status_code = Int(String(rest[:sp2]))
    except:
        pass
    resp.status_text = String(rest[sp2 + 1 :])


fn _parse_header_line(line: String, mut resp: HttpResponse):
    """Parse 'Key: Value' header line."""
    var colon = line.find(":")
    if colon < 0:
        return

    var key = String(line[:colon])
    var val_start = colon + 1
    # Skip leading space after colon
    if val_start < len(line):
        var b = line.as_bytes()
        if b[val_start] == UInt8(ord(" ")):
            val_start += 1
    var val = String(line[val_start:])
    resp.headers[key] = val


fn get_header_ci(resp: HttpResponse, wanted: String) -> String:
    """Case-insensitive header lookup."""
    for item in resp.headers.items():
        if _eq_ascii_ci(item.key, wanted):
            return item.value
    return ""


fn _eq_ascii_ci(a: String, b: String) -> Bool:
    """ASCII-only case-insensitive string equality."""
    if len(a) != len(b):
        return False
    var ab = a.as_bytes()
    var bb = b.as_bytes()
    for i in range(len(a)):
        if _ascii_lower(ab[i]) != _ascii_lower(bb[i]):
            return False
    return True


fn _contains_ascii_ci(haystack: String, needle: String) -> Bool:
    """ASCII-only case-insensitive substring check."""
    if len(needle) == 0:
        return True
    if len(haystack) < len(needle):
        return False

    var hb = haystack.as_bytes()
    var nb = needle.as_bytes()
    for start in range(len(haystack) - len(needle) + 1):
        var ok = True
        for i in range(len(needle)):
            if _ascii_lower(hb[start + i]) != _ascii_lower(nb[i]):
                ok = False
                break
        if ok:
            return True
    return False


fn _ascii_lower(b: UInt8) -> UInt8:
    if b >= UInt8(ord("A")) and b <= UInt8(ord("Z")):
        return b + UInt8(32)
    return b


fn _trim_ascii_spaces(s: String) -> String:
    """Trim ASCII spaces and tabs."""
    if len(s) == 0:
        return s

    var b = s.as_bytes()
    var start = 0
    var stop = len(s)

    while start < stop and (
        b[start] == UInt8(ord(" ")) or b[start] == UInt8(ord("\t"))
    ):
        start += 1

    while stop > start and (
        b[stop - 1] == UInt8(ord(" ")) or b[stop - 1] == UInt8(ord("\t"))
    ):
        stop -= 1

    return String(s[start:stop])


fn _find_chunk_line_end(buffer: String, start: Int) -> Dict[Int, Int]:
    var info = Dict[Int, Int]()
    var rel_crlf = String(buffer[start:]).find("\r\n")
    var rel_lf = String(buffer[start:]).find("\n")

    if rel_crlf >= 0 and (rel_lf < 0 or rel_crlf <= rel_lf):
        info[0] = start + rel_crlf
        info[1] = 2
        return info^
    if rel_lf >= 0:
        info[0] = start + rel_lf
        info[1] = 1
        return info^
    return info^


fn _chunk_data_terminator_len(buffer: String, pos: Int) -> Int:
    if pos + 2 <= len(buffer):
        if String(buffer[pos : pos + 2]) == "\r\n":
            return 2
    if pos + 1 <= len(buffer):
        if String(buffer[pos : pos + 1]) == "\n":
            return 1
    return 0


fn _parse_chunk_size_hex(line: String) raises -> Int:
    """Parse a chunk size line like '1a;ext=value'."""
    var trimmed = _trim_ascii_spaces(line)
    var semi = trimmed.find(";")
    var hex_part = trimmed if semi < 0 else String(trimmed[:semi])

    if len(hex_part) == 0:
        raise Error("Malformed chunked body: empty chunk size")

    var bytes = hex_part.as_bytes()
    var value = 0
    for i in range(len(hex_part)):
        value *= 16
        var c = bytes[i]
        if c >= UInt8(ord("0")) and c <= UInt8(ord("9")):
            value += Int(c - UInt8(ord("0")))
        elif c >= UInt8(ord("a")) and c <= UInt8(ord("f")):
            value += 10 + Int(c - UInt8(ord("a")))
        elif c >= UInt8(ord("A")) and c <= UInt8(ord("F")):
            value += 10 + Int(c - UInt8(ord("A")))
        else:
            raise Error("Malformed chunked body: invalid hex digit in chunk size")
    return value


fn _decode_chunked_body(body: String) raises -> String:
    """Decode HTTP chunked transfer encoding.

    Tolerates both CRLF and bare LF chunk framing line endings.
    """
    var out = String()
    var pos = 0

    while True:
        var line_info = _find_chunk_line_end(body, pos)
        if len(line_info) == 0:
            raise Error("Malformed chunked body: missing chunk size terminator")

        var line_end = line_info[0]
        var term_len = line_info[1]
        var size_line = String(body[pos:line_end])
        var chunk_size = _parse_chunk_size_hex(size_line)
        pos = line_end + term_len

        if chunk_size == 0:
            # Optional trailers follow; ignore them.
            break

        if pos + chunk_size > len(body):
            raise Error("Malformed chunked body: chunk exceeds body length")

        out += String(body[pos : pos + chunk_size])
        pos += chunk_size

        var data_term_len = _chunk_data_terminator_len(body, pos)
        if data_term_len == 0:
            raise Error("Malformed chunked body: missing line ending after chunk data")
        pos += data_term_len

    return out
