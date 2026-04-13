"""OpenRouter streaming client.

Uses the native `http_client` + `sse` stack for HTTPS + SSE transport and
Python interop only for JSON parsing/serialization.

Environment:
    OPENROUTER_API_KEY

Example:
    from llm import OpenRouterClient

    fn main() raises:
        var client = OpenRouterClient.from_env()
        var chunks = client.stream_text("openai/gpt-4o-mini", "Say hello")
        for chunk in chunks:
            print(chunk.delta, end="")
"""

from collections import List
from os import getenv
from python import Python

from http_client import HttpClient, HttpHeader
from http_client.client import ChunkedStreamDecoder
from http_client.net import TcpSocket, resolve_host
from http_client.response import HttpResponse, get_header_ci, parse_response_head
from http_client.tls import TlsSocket
from sse import SseEvent, SseParser


fn _parse_url(
    url: String,
    mut scheme: String,
    mut host: String,
    mut port: String,
    mut path: String,
) raises:
    var rest: String
    if url.startswith("http://"):
        scheme = "http"
        rest = String(url[7:])
    elif url.startswith("https://"):
        scheme = "https"
        rest = String(url[8:])
    else:
        raise Error("URL must start with http:// or https://")

    var slash_pos = rest.find("/")
    var host_port: String
    if slash_pos >= 0:
        host_port = String(rest[:slash_pos])
        path = String(rest[slash_pos:])
    else:
        host_port = rest
        path = "/"

    var colon_pos = host_port.find(":")
    if colon_pos >= 0:
        host = String(host_port[:colon_pos])
        port = String(host_port[colon_pos + 1 :])
    else:
        host = host_port
        port = "443" if scheme == "https" else "80"


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
            var a = hb[start + i]
            var b = nb[i]
            if a >= UInt8(ord("A")) and a <= UInt8(ord("Z")):
                a += UInt8(32)
            if b >= UInt8(ord("A")) and b <= UInt8(ord("Z")):
                b += UInt8(32)
            if a != b:
                ok = False
                break
        if ok:
            return True
    return False


struct OpenRouterChunk(Copyable):
    """One streamed chunk from OpenRouter."""

    var delta: String
    var finish_reason: String
    var raw_json: String

    fn __init__(out self):
        self.delta = ""
        self.finish_reason = ""
        self.raw_json = ""

    fn __init__(
        out self,
        delta: String,
        finish_reason: String = "",
        raw_json: String = "",
    ):
        self.delta = delta
        self.finish_reason = finish_reason
        self.raw_json = raw_json


struct OpenRouterClient:
    """Minimal OpenRouter client using OpenAI-compatible chat completions."""

    var api_key: String
    var base_url: String
    var http: HttpClient
    var referer: String
    var title: String

    fn __init__(
        out self,
        api_key: String,
        base_url: String = "https://openrouter.ai/api/v1",
        referer: String = "https://github.com/automata/modex",
        title: String = "modex",
    ):
        self.api_key = api_key
        self.base_url = base_url
        self.http = HttpClient("modex/0.1 (Mojo)")
        self.referer = referer
        self.title = title

    @staticmethod
    fn from_env() raises -> Self:
        """Create a client from OPENROUTER_API_KEY."""
        var key = getenv("OPENROUTER_API_KEY")
        if len(key) == 0:
            raise Error("OPENROUTER_API_KEY is not set")
        return Self(key)

    fn stream_text(self, model: String, prompt: String) raises -> List[OpenRouterChunk]:
        """Stream a simple single-user-message chat completion."""
        var messages = List[String]()
        messages.append(prompt)
        return self.stream_messages(model, messages)

    fn stream_text_live(
        self,
        model: String,
        prompt: String,
        on_chunk: fn(OpenRouterChunk) -> NoneType,
    ) raises:
        """Stream text and invoke callback for each chunk as it arrives."""
        var messages = List[String]()
        messages.append(prompt)
        self.stream_messages_live(model, messages, on_chunk)

    fn stream_messages(
        self,
        model: String,
        user_messages: List[String],
        system_prompt: String = "",
    ) raises -> List[OpenRouterChunk]:
        """Collect all streamed chat completion chunks into a list."""
        var payload = self._build_payload(model, user_messages, system_prompt)
        var headers = self._build_headers()
        var events = self.http.post_sse(
            self.base_url + "/chat/completions",
            payload,
            "application/json",
            headers,
        )
        return self._parse_stream(events)

    fn stream_messages_live(
        self,
        model: String,
        user_messages: List[String],
        on_chunk: fn(OpenRouterChunk) -> NoneType,
        system_prompt: String = "",
    ) raises:
        """Perform true live streaming and invoke callback per chunk."""
        var payload = self._build_payload(model, user_messages, system_prompt)
        var headers = self._build_headers()
        var url = self.base_url + "/chat/completions"

        var scheme = String()
        var host = String()
        var port = String()
        var path = String()
        _parse_url(url, scheme, host, port, path)

        var addr = resolve_host(host, port)
        var req = self._build_request(host, path, payload, headers)
        var parser = SseParser()

        if scheme == "https":
            var sock = TlsSocket()
            sock.connect(host, addr)
            _ = sock.send_all(req)
            var headers_and_rest = self._read_headers_tls(sock)
            var response_head = parse_response_head(headers_and_rest[0])
            if response_head.status_code < 200 or response_head.status_code >= 300:
                sock.close()
                raise Error("OpenRouter returned HTTP " + String(response_head.status_code))
            self._consume_stream_tls(sock, response_head, headers_and_rest[1], parser, on_chunk)
            sock.close()
        else:
            var sock = TcpSocket()
            sock.connect(addr)
            _ = sock.send_all(req)
            var headers_and_rest = self._read_headers_tcp(sock)
            var response_head = parse_response_head(headers_and_rest[0])
            if response_head.status_code < 200 or response_head.status_code >= 300:
                sock.close()
                raise Error("OpenRouter returned HTTP " + String(response_head.status_code))
            self._consume_stream_tcp(sock, response_head, headers_and_rest[1], parser, on_chunk)
            sock.close()

    fn _consume_stream_tls(
        self,
        sock: TlsSocket,
        response_head: HttpResponse,
        initial_body: String,
        mut parser: SseParser,
        on_chunk: fn(OpenRouterChunk) -> NoneType,
    ) raises:
        var te = get_header_ci(response_head, "Transfer-Encoding")
        if _contains_ascii_ci(te, "chunked"):
            var decoder = ChunkedStreamDecoder()
            self._emit_from_sse_data(parser.feed(decoder.feed(initial_body)), on_chunk)
            while not decoder.done:
                var chunk = sock.recv(4096)
                if len(chunk) == 0:
                    break
                self._emit_from_sse_data(parser.feed(decoder.feed(chunk)), on_chunk)
        else:
            self._emit_from_sse_data(parser.feed(initial_body), on_chunk)
            while True:
                var chunk = sock.recv(4096)
                if len(chunk) == 0:
                    break
                self._emit_from_sse_data(parser.feed(chunk), on_chunk)
        self._emit_from_sse_data(parser.finish(), on_chunk)

    fn _consume_stream_tcp(
        self,
        sock: TcpSocket,
        response_head: HttpResponse,
        initial_body: String,
        mut parser: SseParser,
        on_chunk: fn(OpenRouterChunk) -> NoneType,
    ) raises:
        var te = get_header_ci(response_head, "Transfer-Encoding")
        if _contains_ascii_ci(te, "chunked"):
            var decoder = ChunkedStreamDecoder()
            self._emit_from_sse_data(parser.feed(decoder.feed(initial_body)), on_chunk)
            while not decoder.done:
                var chunk = sock.recv(4096)
                if len(chunk) == 0:
                    break
                self._emit_from_sse_data(parser.feed(decoder.feed(chunk)), on_chunk)
        else:
            self._emit_from_sse_data(parser.feed(initial_body), on_chunk)
            while True:
                var chunk = sock.recv(4096)
                if len(chunk) == 0:
                    break
                self._emit_from_sse_data(parser.feed(chunk), on_chunk)
        self._emit_from_sse_data(parser.finish(), on_chunk)

    fn _build_headers(self) -> List[HttpHeader]:
        var headers = List[HttpHeader]()
        headers.append(HttpHeader("Authorization", "Bearer " + self.api_key))
        headers.append(HttpHeader("Accept", "text/event-stream"))
        headers.append(HttpHeader("HTTP-Referer", self.referer))
        headers.append(HttpHeader("X-Title", self.title))
        return headers^

    fn _build_request(
        self,
        host: String,
        path: String,
        body: String,
        headers: List[HttpHeader],
    ) -> String:
        var req = "POST " + path + " HTTP/1.1\r\n"
        req += "Host: " + host + "\r\n"
        req += "Connection: close\r\n"
        req += "User-Agent: modex/0.1 (Mojo)\r\n"
        for header in headers:
            req += header.name + ": " + header.value + "\r\n"
        req += "Content-Type: application/json\r\n"
        req += "Content-Length: " + String(len(body)) + "\r\n"
        req += "\r\n"
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

    fn _build_payload(
        self,
        model: String,
        user_messages: List[String],
        system_prompt: String,
    ) raises -> String:
        var py_json = Python.import_module("json")
        var py_messages = Python.list()

        if len(system_prompt) > 0:
            var system_msg = Python.dict()
            system_msg["role"] = "system"
            system_msg["content"] = system_prompt
            py_messages.append(system_msg)

        for message in user_messages:
            var user_msg = Python.dict()
            user_msg["role"] = "user"
            user_msg["content"] = message
            py_messages.append(user_msg)

        var payload = Python.dict()
        payload["model"] = model
        payload["messages"] = py_messages
        payload["stream"] = True

        return String(py_json.dumps(payload))

    fn _emit_from_sse_data(
        self,
        events: List[SseEvent],
        on_chunk: fn(OpenRouterChunk) -> NoneType,
    ) raises:
        var py_json = Python.import_module("json")
        for event in events:
            if len(event.data) == 0:
                continue
            if event.data == "[DONE]":
                return
            try:
                var obj = py_json.loads(event.data)
                var choices = obj.get("choices", Python.list())
                if len(choices) == 0:
                    continue
                var choice0 = choices[0]
                var delta_obj = choice0.get("delta", Python.dict())
                var delta = String(delta_obj.get("content", ""))
                var finish_reason = String(choice0.get("finish_reason", ""))
                if len(delta) > 0 or len(finish_reason) > 0:
                    on_chunk(OpenRouterChunk(delta, finish_reason, event.data))
            except:
                pass

    fn _parse_stream(self, events: List[SseEvent]) raises -> List[OpenRouterChunk]:
        """Parse OpenRouter/OpenAI-compatible SSE events into text deltas."""
        var chunks = List[OpenRouterChunk]()
        var py_json = Python.import_module("json")

        for event in events:
            if len(event.data) == 0:
                continue
            if event.data == "[DONE]":
                break

            try:
                var obj = py_json.loads(event.data)
                var choices = obj.get("choices", Python.list())
                if len(choices) == 0:
                    continue

                var choice0 = choices[0]
                var delta_obj = choice0.get("delta", Python.dict())
                var delta = String(delta_obj.get("content", ""))
                var finish_reason = String(choice0.get("finish_reason", ""))

                if len(delta) > 0 or len(finish_reason) > 0:
                    chunks.append(OpenRouterChunk(delta, finish_reason, event.data))
            except:
                pass

        return chunks^
