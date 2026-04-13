"""HTTP client: high-level API for making HTTP/1.1 requests."""

from collections import List
from sse import SseEvent, SseParser


struct HttpHeader(Copyable):
    var name: String
    var value: String

    fn __init__(out self):
        self.name = ""
        self.value = ""

    fn __init__(out self, name: String, value: String):
        self.name = name
        self.value = value

from .net import TcpSocket, resolve_host
from .response import HttpResponse, get_header_ci, parse_response, parse_response_head
from .tls import TlsSocket


fn _parse_url(
    url: String,
    mut scheme: String,
    mut host: String,
    mut port: String,
    mut path: String,
) raises:
    """Parse 'http[s]://host[:port]/path' into components."""
    var rest: String

    # Strip scheme
    if url.startswith("http://"):
        scheme = "http"
        rest = String(url[7:])
    elif url.startswith("https://"):
        scheme = "https"
        rest = String(url[8:])
    else:
        raise Error("URL must start with http:// or https://")

    # Split host from path at first /
    var slash_pos = rest.find("/")

    var host_port: String
    if slash_pos >= 0:
        host_port = String(rest[:slash_pos])
        path = String(rest[slash_pos:])
    else:
        host_port = rest
        path = "/"

    # Split host:port
    var colon_pos = host_port.find(":")
    if colon_pos >= 0:
        host = String(host_port[:colon_pos])
        port = String(host_port[colon_pos + 1 :])
    else:
        host = host_port
        port = "443" if scheme == "https" else "80"


struct ChunkedStreamDecoder:
    """Incremental decoder for HTTP chunked transfer encoding."""

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
                var line_end = self.buffer.find("\r\n")
                if line_end < 0:
                    break
                var size_line = String(self.buffer[:line_end])
                self.current_chunk_size = _parse_chunk_size_line(size_line)
                self.buffer = String(self.buffer[line_end + 2 :])
                if self.current_chunk_size == 0:
                    self.done = True
                    break

            if len(self.buffer) < self.current_chunk_size + 2:
                break

            out += String(self.buffer[: self.current_chunk_size])
            if String(self.buffer[self.current_chunk_size : self.current_chunk_size + 2]) != "\r\n":
                raise Error("Malformed chunked stream: missing CRLF after chunk")
            self.buffer = String(self.buffer[self.current_chunk_size + 2 :])
            self.current_chunk_size = -1

        return out


fn _parse_chunk_size_line(line: String) raises -> Int:
    var semi = line.find(";")
    var hex_part = line if semi < 0 else String(line[:semi])
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
            raise Error("Malformed chunked stream: invalid hex digit")
    return value


fn _append_events(mut dst: List[SseEvent], src: List[SseEvent]):
    for event in src:
        dst.append(event.copy())


fn _ascii_lower(b: UInt8) -> UInt8:
    if b >= UInt8(ord("A")) and b <= UInt8(ord("Z")):
        return b + UInt8(32)
    return b


fn _contains_ascii_ci(haystack: String, needle: String) -> Bool:
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


struct HttpClient:
    """Minimal blocking HTTP/1.1 client (plain HTTP only).

    Example:
        var client = HttpClient()
        var resp = client.get("http://example.com/")
        print(resp.status_code, resp.body)
    """

    var user_agent: String

    fn __init__(out self, user_agent: String = "modex/0.1 (Mojo)"):
        self.user_agent = user_agent

    fn get(self, url: String) raises -> HttpResponse:
        """Perform an HTTP GET request."""
        return self.request("GET", url)

    fn get_sse(self, url: String) raises -> List[SseEvent]:
        """Perform an HTTP GET request and incrementally parse an SSE stream.

        This reads the response body incrementally and feeds chunks into
        `SseParser`. Returned events are collected in memory for now.
        """
        return self.request_sse("GET", url)

    fn post(
        self,
        url: String,
        body: String = "",
        content_type: String = "application/json",
    ) raises -> HttpResponse:
        """Perform an HTTP POST request."""
        return self.request("POST", url, body, content_type)

    fn post_with_headers(
        self,
        url: String,
        body: String,
        content_type: String,
        headers: List[HttpHeader],
    ) raises -> HttpResponse:
        """Perform an HTTP POST request with custom headers."""
        return self.request_with_headers("POST", url, body, content_type, headers)

    fn post_sse(
        self,
        url: String,
        body: String,
        content_type: String,
        headers: List[HttpHeader],
    ) raises -> List[SseEvent]:
        """Perform an HTTP POST request and parse an SSE response."""
        return self.request_sse_with_headers("POST", url, body, content_type, headers)

    fn request(
        self,
        method: String,
        url: String,
        body: String = "",
        content_type: String = "",
    ) raises -> HttpResponse:
        """Perform an HTTP request."""
        return self.request_with_headers(
            method,
            url,
            body,
            content_type,
            List[HttpHeader](),
        )

    fn request_with_headers(
        self,
        method: String,
        url: String,
        body: String,
        content_type: String,
        headers: List[HttpHeader],
    ) raises -> HttpResponse:
        """Perform an HTTP request with custom headers."""
        var scheme = String()
        var host = String()
        var port = String()
        var path = String()
        _parse_url(url, scheme, host, port, path)

        var addr = resolve_host(host, port)
        var req = self._build_request(method, host, path, body, content_type, headers)

        if scheme == "https":
            var sock = TlsSocket()
            sock.connect(host, addr)
            _ = sock.send_all(req)
            var raw = sock.recv_all()
            sock.close()
            return parse_response(raw)
        else:
            var sock = TcpSocket()
            sock.connect(addr)
            _ = sock.send_all(req)
            var raw = sock.recv_all()
            sock.close()
            return parse_response(raw)

    fn request_sse(self, method: String, url: String) raises -> List[SseEvent]:
        """Perform an HTTP request and incrementally parse SSE events."""
        return self.request_sse_with_headers(
            method,
            url,
            "",
            "",
            List[HttpHeader](),
        )

    fn request_sse_with_headers(
        self,
        method: String,
        url: String,
        body: String,
        content_type: String,
        headers: List[HttpHeader],
    ) raises -> List[SseEvent]:
        """Perform an HTTP request and incrementally parse SSE events."""
        var scheme = String()
        var host = String()
        var port = String()
        var path = String()
        _parse_url(url, scheme, host, port, path)

        var addr = resolve_host(host, port)
        var req = self._build_request(method, host, path, body, content_type, headers)
        var parser = SseParser()
        var events = List[SseEvent]()

        if scheme == "https":
            var sock = TlsSocket()
            sock.connect(host, addr)
            _ = sock.send_all(req)
            var headers_and_rest = self._read_headers_tls(sock)
            var response_head = parse_response_head(headers_and_rest[0])
            var transfer_encoding = get_header_ci(response_head, "Transfer-Encoding")
            if _contains_ascii_ci(transfer_encoding, "chunked"):
                var decoder = ChunkedStreamDecoder()
                var body_chunk = decoder.feed(headers_and_rest[1])
                _append_events(events, parser.feed(body_chunk))
                while not decoder.done:
                    var chunk = sock.recv(4096)
                    if len(chunk) == 0:
                        break
                    var decoded = decoder.feed(chunk)
                    _append_events(events, parser.feed(decoded))
            else:
                _append_events(events, parser.feed(headers_and_rest[1]))
                while True:
                    var chunk = sock.recv(4096)
                    if len(chunk) == 0:
                        break
                    _append_events(events, parser.feed(chunk))
            sock.close()
            return events^
        else:
            var sock = TcpSocket()
            sock.connect(addr)
            _ = sock.send_all(req)
            var headers_and_rest = self._read_headers_tcp(sock)
            var response_head = parse_response_head(headers_and_rest[0])
            var transfer_encoding = get_header_ci(response_head, "Transfer-Encoding")
            if _contains_ascii_ci(transfer_encoding, "chunked"):
                var decoder = ChunkedStreamDecoder()
                var body_chunk = decoder.feed(headers_and_rest[1])
                _append_events(events, parser.feed(body_chunk))
                while not decoder.done:
                    var chunk = sock.recv(4096)
                    if len(chunk) == 0:
                        break
                    var decoded = decoder.feed(chunk)
                    _append_events(events, parser.feed(decoded))
            else:
                _append_events(events, parser.feed(headers_and_rest[1]))
                while True:
                    var chunk = sock.recv(4096)
                    if len(chunk) == 0:
                        break
                    _append_events(events, parser.feed(chunk))
            sock.close()
            return events^

    fn _build_request(
        self,
        method: String,
        host: String,
        path: String,
        body: String,
        content_type: String,
        headers: List[HttpHeader],
    ) -> String:
        var req = method + " " + path + " HTTP/1.1\r\n"
        req += "Host: " + host + "\r\n"
        req += "Connection: close\r\n"
        req += "User-Agent: " + self.user_agent + "\r\n"

        for header in headers:
            req += header.name + ": " + header.value + "\r\n"

        if len(body) > 0:
            req += "Content-Length: " + String(len(body)) + "\r\n"
            if len(content_type) > 0:
                req += "Content-Type: " + content_type + "\r\n"

        req += "\r\n"
        if len(body) > 0:
            req += body
        return req

    fn _read_headers_tcp(self, sock: TcpSocket) raises -> List[String]:
        var buffer = String()
        while True:
            var chunk = sock.recv(4096)
            if len(chunk) == 0:
                raise Error("Connection closed before HTTP headers were received")
            buffer += chunk
            var sep = buffer.find("\r\n\r\n")
            if sep >= 0:
                var result = List[String]()
                result.append(String(buffer[:sep]))
                result.append(String(buffer[sep + 4 :]))
                return result^

    fn _read_headers_tls(self, sock: TlsSocket) raises -> List[String]:
        var buffer = String()
        while True:
            var chunk = sock.recv(4096)
            if len(chunk) == 0:
                raise Error("Connection closed before HTTP headers were received")
            buffer += chunk
            var sep = buffer.find("\r\n\r\n")
            if sep >= 0:
                var result = List[String]()
                result.append(String(buffer[:sep]))
                result.append(String(buffer[sep + 4 :]))
                return result^
