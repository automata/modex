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

    # Split header section into lines on \r\n
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

    return resp^


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
