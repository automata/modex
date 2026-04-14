"""Shared HTTP chunked transfer decoding helpers."""

from collections import List


struct ChunkedStreamDecoder:
    """Incremental decoder for HTTP chunked transfer encoding.

    Some servers in streaming mode are lax about using bare `\n` instead of
    `\r\n` between chunk framing lines. We accept both here.
    """

    var buffer: String
    var current_chunk_size: Int
    var done: Bool

    fn __init__(out self):
        self.buffer = ""
        self.current_chunk_size = -1
        self.done = False

    fn feed(mut self, chunk: String) raises -> String:
        """Feed raw chunked bytes, return decoded body bytes."""
        if self.done:
            return ""

        self.buffer += chunk
        var out = String()

        while True:
            if self.current_chunk_size < 0:
                var size_info = _find_chunk_line_end(self.buffer, 0)
                if len(size_info) == 0:
                    break
                var line_end = size_info[0]
                var term_len = size_info[1]
                var size_line = String(self.buffer[:line_end])
                self.current_chunk_size = _parse_chunk_size_hex(size_line)
                self.buffer = String(self.buffer[line_end + term_len :])
                if self.current_chunk_size == 0:
                    self.done = True
                    break

            if len(self.buffer) < self.current_chunk_size:
                break

            out += String(self.buffer[: self.current_chunk_size])

            if len(self.buffer) == self.current_chunk_size:
                break

            var term_len = _chunk_data_terminator_len(self.buffer, self.current_chunk_size)
            if term_len == 0:
                if len(self.buffer) < self.current_chunk_size + 2:
                    break
                raise Error("Malformed chunked stream: missing line ending after chunk")
            self.buffer = String(self.buffer[self.current_chunk_size + term_len :])
            self.current_chunk_size = -1

        return out


fn decode_chunked_body(body: String) raises -> String:
    """Decode a full HTTP chunked body.

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


fn _find_chunk_line_end(buffer: String, start: Int) -> List[Int]:
    var info = List[Int]()
    var tail = String(buffer[start:])
    var rel_crlf = tail.find("\r\n")
    var rel_lf = tail.find("\n")

    if rel_crlf >= 0 and (rel_lf < 0 or rel_crlf <= rel_lf):
        info.append(start + rel_crlf)
        info.append(2)
        return info^
    if rel_lf >= 0:
        info.append(start + rel_lf)
        info.append(1)
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


fn _trim_ascii_spaces(s: String) -> String:
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


fn _parse_chunk_size_hex(line: String) raises -> Int:
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
