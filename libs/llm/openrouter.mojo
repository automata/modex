"""OpenRouter streaming client.

Uses the native `http_client` + `sse` + `json` stack for HTTPS, SSE, and JSON.

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

from http_client import HttpClient, HttpHeader
from http_client.client import ChunkedStreamDecoder
from http_client.net import TcpSocket, resolve_host
from http_client.response import HttpResponse, get_header_ci, parse_response_head
from http_client.tls import TlsSocket
from json import JsonArrayBuilder, JsonObjectBuilder, parse_json, json_quote
from sse import SseEvent, SseParser
from tools import ToolDefinition, builtin_tool_definitions, execute_builtin_tool

from .history import SessionHistory, SessionMessage
from .types import OpenRouterChunk, OpenRouterToolCall, OpenRouterToolSpec


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

    fn stream_text_with_tools(
        self,
        model: String,
        prompt: String,
        tools: List[OpenRouterToolSpec],
    ) raises -> List[OpenRouterChunk]:
        """Stream a simple prompt with tool definitions."""
        var messages = List[String]()
        messages.append(prompt)
        return self.stream_messages_with_tools(model, messages, tools)

    fn stream_text_live(
        self,
        model: String,
        prompt: String,
        on_chunk: fn(OpenRouterChunk) -> NoneType,
    ) raises:
        """Stream text and invoke callback for each chunk as it arrives."""
        var messages = List[String]()
        messages.append(prompt)
        var empty_tools = List[OpenRouterToolSpec]()
        self.stream_messages_live(model, messages, on_chunk, empty_tools)

    fn run_with_read_tool(
        self,
        model: String,
        prompt: String,
        max_turns: Int = 4,
        system_prompt: String = "",
    ) raises -> String:
        """Backward-compatible alias for the generic built-in tool loop."""
        var defs = List[ToolDefinition]()
        var all_defs = builtin_tool_definitions()
        for d in all_defs:
            if d.name == "read":
                defs.append(d.copy())
        return self.run_with_builtin_tools(model, prompt, defs, max_turns, system_prompt)

    fn run_with_default_builtin_tools(
        self,
        model: String,
        prompt: String,
        max_turns: Int = 6,
        system_prompt: String = "",
    ) raises -> String:
        """Run the generic loop with the default built-in tool set."""
        var defs = builtin_tool_definitions()
        return self.run_with_builtin_tools(model, prompt, defs, max_turns, system_prompt)

    fn run_with_default_builtin_tools_live(
        self,
        model: String,
        prompt: String,
        on_chunk: fn(OpenRouterChunk) -> NoneType,
        max_turns: Int = 6,
        system_prompt: String = "",
    ) raises -> String:
        """Live callback version of the default built-in tool loop."""
        var defs = builtin_tool_definitions()
        return self.run_with_builtin_tools_live(model, prompt, defs, on_chunk, max_turns, system_prompt)

    fn run_with_builtin_tools(
        self,
        model: String,
        prompt: String,
        tool_defs: List[ToolDefinition],
        max_turns: Int = 6,
        system_prompt: String = "",
    ) raises -> String:
        """Run a generic multi-turn loop with built-in tools.

        This sends tool schemas, collects streamed tool calls, executes the
        matching local tools, sends tool results back, and repeats until the
        model returns final assistant text.
        """
        var tools = List[OpenRouterToolSpec]()
        for d in tool_defs:
            tools.append(OpenRouterToolSpec(d.name, d.description, d.parameters_json_schema))

        var history = SessionHistory()
        if len(system_prompt) > 0:
            history.append_system(system_prompt)
        history.append_user(prompt)

        for _turn in range(max_turns):
            var payload = self._build_payload_from_history(model, history, tools)
            var headers = self._build_headers()
            var events = self.http.post_sse(
                self.base_url + "/chat/completions",
                payload,
                "application/json",
                headers,
            )
            var chunks = self._parse_stream(events)
            var calls = assemble_tool_calls(chunks)

            if len(calls) == 0:
                return _concat_text_deltas(chunks)

            history.append_assistant_tool_calls(calls)

            for call in calls:
                var tool_result = self._execute_tool_call(call)
                history.append_tool_result(call.id, tool_result)

        raise Error("run_with_builtin_tools exceeded max_turns without a final response")

    fn run_with_builtin_tools_live(
        self,
        model: String,
        prompt: String,
        tool_defs: List[ToolDefinition],
        on_chunk: fn(OpenRouterChunk) -> NoneType,
        max_turns: Int = 6,
        system_prompt: String = "",
    ) raises -> String:
        """Live callback version of the generic built-in tool loop."""
        var tools = List[OpenRouterToolSpec]()
        for d in tool_defs:
            tools.append(OpenRouterToolSpec(d.name, d.description, d.parameters_json_schema))

        var history = SessionHistory()
        if len(system_prompt) > 0:
            history.append_system(system_prompt)
        history.append_user(prompt)

        for _turn in range(max_turns):
            var payload = self._build_payload_from_history(model, history, tools)
            var chunks = self._stream_payload_live_collect(payload, on_chunk)
            var calls = assemble_tool_calls(chunks)

            if len(calls) == 0:
                return _concat_text_deltas(chunks)

            history.append_assistant_tool_calls(calls)

            for call in calls:
                var tool_result = self._execute_tool_call(call)
                history.append_tool_result(call.id, tool_result)

        raise Error("run_with_builtin_tools_live exceeded max_turns without a final response")

    fn stream_text_with_tools_live(
        self,
        model: String,
        prompt: String,
        tools: List[OpenRouterToolSpec],
        on_chunk: fn(OpenRouterChunk) -> NoneType,
    ) raises:
        """Stream a prompt with tools and invoke callback live."""
        var messages = List[String]()
        messages.append(prompt)
        self.stream_messages_live(model, messages, on_chunk, tools)

    fn stream_messages(
        self,
        model: String,
        user_messages: List[String],
        system_prompt: String = "",
    ) raises -> List[OpenRouterChunk]:
        """Collect all streamed chat completion chunks into a list."""
        var empty_tools = List[OpenRouterToolSpec]()
        return self.stream_messages_with_tools(
            model,
            user_messages,
            empty_tools,
            system_prompt,
        )

    fn stream_messages_with_tools(
        self,
        model: String,
        user_messages: List[String],
        tools: List[OpenRouterToolSpec],
        system_prompt: String = "",
    ) raises -> List[OpenRouterChunk]:
        """Collect all streamed chat/tool-call chunks into a list."""
        var payload = self._build_payload(model, user_messages, system_prompt, tools)
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
        tools: List[OpenRouterToolSpec] = List[OpenRouterToolSpec](),
        system_prompt: String = "",
    ) raises:
        """Perform true live streaming and invoke callback per chunk."""
        var payload = self._build_payload(model, user_messages, system_prompt, tools)
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

    fn _execute_tool_call(self, call: OpenRouterToolCall) raises -> String:
        try:
            return execute_builtin_tool(call.function_name, call.arguments)
        except e:
            return "Error executing tool '" + call.function_name + "': " + String(e)

    fn _build_payload(
        self,
        model: String,
        user_messages: List[String],
        system_prompt: String,
        tools: List[OpenRouterToolSpec],
    ) raises -> String:
        var history = SessionHistory()
        if len(system_prompt) > 0:
            history.append_system(system_prompt)
        for message in user_messages:
            history.append_user(message)
        return self._build_payload_from_history(model, history, tools)

    fn _build_payload_from_history(
        self,
        model: String,
        history: SessionHistory,
        tools: List[OpenRouterToolSpec],
    ) raises -> String:
        var payload = JsonObjectBuilder()
        payload.add_string("model", model)
        payload.add_raw("messages", _history_to_messages_json(history))
        payload.add_bool("stream", True)
        if len(tools) > 0:
            payload.add_raw("tools", _tools_to_json(tools))
        return payload.finish()

    fn _stream_payload_live_collect(
        self,
        payload: String,
        on_chunk: fn(OpenRouterChunk) -> NoneType,
    ) raises -> List[OpenRouterChunk]:
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
        var collected = List[OpenRouterChunk]()

        if scheme == "https":
            var sock = TlsSocket()
            sock.connect(host, addr)
            _ = sock.send_all(req)
            var headers_and_rest = self._read_headers_tls(sock)
            var response_head = parse_response_head(headers_and_rest[0])
            if response_head.status_code < 200 or response_head.status_code >= 300:
                sock.close()
                raise Error("OpenRouter returned HTTP " + String(response_head.status_code))
            self._consume_stream_tls_collect(sock, response_head, headers_and_rest[1], parser, on_chunk, collected)
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
            self._consume_stream_tcp_collect(sock, response_head, headers_and_rest[1], parser, on_chunk, collected)
            sock.close()

        return collected^

    fn _consume_stream_tls_collect(
        self,
        sock: TlsSocket,
        response_head: HttpResponse,
        initial_body: String,
        mut parser: SseParser,
        on_chunk: fn(OpenRouterChunk) -> NoneType,
        mut collected: List[OpenRouterChunk],
    ) raises:
        var te = get_header_ci(response_head, "Transfer-Encoding")
        if _contains_ascii_ci(te, "chunked"):
            var decoder = ChunkedStreamDecoder()
            self._emit_and_collect_from_sse_data(parser.feed(decoder.feed(initial_body)), on_chunk, collected)
            while not decoder.done:
                var chunk = sock.recv(4096)
                if len(chunk) == 0:
                    break
                self._emit_and_collect_from_sse_data(parser.feed(decoder.feed(chunk)), on_chunk, collected)
        else:
            self._emit_and_collect_from_sse_data(parser.feed(initial_body), on_chunk, collected)
            while True:
                var chunk = sock.recv(4096)
                if len(chunk) == 0:
                    break
                self._emit_and_collect_from_sse_data(parser.feed(chunk), on_chunk, collected)
        self._emit_and_collect_from_sse_data(parser.finish(), on_chunk, collected)

    fn _consume_stream_tcp_collect(
        self,
        sock: TcpSocket,
        response_head: HttpResponse,
        initial_body: String,
        mut parser: SseParser,
        on_chunk: fn(OpenRouterChunk) -> NoneType,
        mut collected: List[OpenRouterChunk],
    ) raises:
        var te = get_header_ci(response_head, "Transfer-Encoding")
        if _contains_ascii_ci(te, "chunked"):
            var decoder = ChunkedStreamDecoder()
            self._emit_and_collect_from_sse_data(parser.feed(decoder.feed(initial_body)), on_chunk, collected)
            while not decoder.done:
                var chunk = sock.recv(4096)
                if len(chunk) == 0:
                    break
                self._emit_and_collect_from_sse_data(parser.feed(decoder.feed(chunk)), on_chunk, collected)
        else:
            self._emit_and_collect_from_sse_data(parser.feed(initial_body), on_chunk, collected)
            while True:
                var chunk = sock.recv(4096)
                if len(chunk) == 0:
                    break
                self._emit_and_collect_from_sse_data(parser.feed(chunk), on_chunk, collected)
        self._emit_and_collect_from_sse_data(parser.finish(), on_chunk, collected)

    fn _emit_from_sse_data(
        self,
        events: List[SseEvent],
        on_chunk: fn(OpenRouterChunk) -> NoneType,
    ) raises:
        for event in events:
            var parsed = self._parse_event_chunks(event)
            for chunk in parsed:
                on_chunk(chunk)

    fn _emit_and_collect_from_sse_data(
        self,
        events: List[SseEvent],
        on_chunk: fn(OpenRouterChunk) -> NoneType,
        mut collected: List[OpenRouterChunk],
    ) raises:
        for event in events:
            var parsed = self._parse_event_chunks(event)
            for chunk in parsed:
                on_chunk(chunk)
                collected.append(chunk.copy())

    fn _parse_stream(self, events: List[SseEvent]) raises -> List[OpenRouterChunk]:
        """Parse OpenRouter/OpenAI-compatible SSE events into chunks."""
        var chunks = List[OpenRouterChunk]()
        for event in events:
            var parsed = self._parse_event_chunks(event)
            for chunk in parsed:
                chunks.append(chunk.copy())
        return chunks^

    fn _parse_event_chunks(self, event: SseEvent) raises -> List[OpenRouterChunk]:
        """Parse one SSE event into one or more chunks.

        A single SSE frame may contain:
        - a text delta
        - one or more tool_call deltas
        - a finish reason
        """
        var out = List[OpenRouterChunk]()
        if len(event.data) == 0 or event.data == "[DONE]":
            return out^

        try:
            var obj = parse_json(event.data)
            var choices = obj.get("choices")
            if choices.is_missing() or choices.len() == 0:
                return out^

            var choice0 = choices.item(0)
            var delta_obj = choice0.get("delta")

            var text_delta = String()
            var content = delta_obj.get("content")
            if not content.is_missing() and content.kind() == "string":
                text_delta = content.as_string()

            var finish_reason = String()
            var finish = choice0.get("finish_reason")
            if not finish.is_missing() and not finish.is_null() and finish.kind() == "string":
                finish_reason = finish.as_string()

            if len(text_delta) > 0 or len(finish_reason) > 0:
                out.append(OpenRouterChunk(text_delta, finish_reason, event.data))

            var tool_calls = delta_obj.get("tool_calls")
            if not tool_calls.is_missing() and tool_calls.kind() == "array":
                for i in range(tool_calls.len()):
                    var tool_call = tool_calls.item(i)
                    var index = 0
                    var index_val = tool_call.get("index")
                    if not index_val.is_missing():
                        index = index_val.as_int()
                    var id = String()
                    var id_val = tool_call.get("id")
                    if not id_val.is_missing() and id_val.kind() == "string":
                        id = id_val.as_string()
                    var function_obj = tool_call.get("function")
                    var function_name = String()
                    var fn_name_val = function_obj.get("name")
                    if not fn_name_val.is_missing() and fn_name_val.kind() == "string":
                        function_name = fn_name_val.as_string()
                    var arguments = String()
                    var args_val = function_obj.get("arguments")
                    if not args_val.is_missing() and args_val.kind() == "string":
                        arguments = args_val.as_string()
                    out.append(
                        OpenRouterChunk(
                            "",
                            finish_reason,
                            event.data,
                            index,
                            id,
                            function_name,
                            arguments,
                        )
                    )
        except:
            pass

        return out^


fn assemble_tool_calls(chunks: List[OpenRouterChunk]) -> List[OpenRouterToolCall]:
    """Assemble full tool calls from streamed OpenRouter chunks.

    OpenAI-compatible streaming sends tool calls in partial deltas keyed by
    `index`. This helper merges all deltas into complete tool calls.
    """
    var calls = List[OpenRouterToolCall]()

    for chunk in chunks:
        if not chunk.has_tool_call():
            continue

        var found = False
        for i in range(len(calls)):
            if calls[i].index == chunk.tool_call_index:
                found = True
                if len(chunk.tool_call_id) > 0:
                    calls[i].id = chunk.tool_call_id
                if len(chunk.tool_call_name) > 0:
                    calls[i].function_name = chunk.tool_call_name
                calls[i].arguments += chunk.tool_call_arguments
                break

        if not found:
            calls.append(
                OpenRouterToolCall(
                    chunk.tool_call_index,
                    chunk.tool_call_id,
                    chunk.tool_call_name,
                    chunk.tool_call_arguments,
                )
            )

    return calls^


fn _concat_text_deltas(chunks: List[OpenRouterChunk]) -> String:
    var out = String()
    for chunk in chunks:
        if len(chunk.delta) > 0:
            out += chunk.delta
    return out


fn _tool_call_to_json(call: OpenRouterToolCall) -> String:
    var function_obj = JsonObjectBuilder()
    function_obj.add_string("name", call.function_name)
    function_obj.add_string("arguments", call.arguments)

    var tool_call_obj = JsonObjectBuilder()
    tool_call_obj.add_string("id", call.id)
    tool_call_obj.add_string("type", "function")
    tool_call_obj.add_raw("function", function_obj.finish())
    return tool_call_obj.finish()


fn _message_to_json(msg: SessionMessage) -> String:
    var obj = JsonObjectBuilder()
    obj.add_string("role", msg.role)
    if msg.role == "assistant":
        obj.add_string("content", msg.content)
        if len(msg.tool_calls) > 0:
            var arr = JsonArrayBuilder()
            for call in msg.tool_calls:
                arr.add_raw(_tool_call_to_json(call))
            obj.add_raw("tool_calls", arr.finish())
    elif msg.role == "tool":
        obj.add_string("tool_call_id", msg.tool_call_id)
        obj.add_string("content", msg.content)
    else:
        obj.add_string("content", msg.content)
    return obj.finish()


fn _history_to_messages_json(history: SessionHistory) -> String:
    var arr = JsonArrayBuilder()
    for msg in history.messages:
        arr.add_raw(_message_to_json(msg))
    return arr.finish()


fn _tools_to_json(tools: List[OpenRouterToolSpec]) -> String:
    var arr = JsonArrayBuilder()
    for tool in tools:
        var function_obj = JsonObjectBuilder()
        function_obj.add_string("name", tool.name)
        function_obj.add_string("description", tool.description)
        function_obj.add_raw("parameters", tool.parameters_json_schema)

        var tool_obj = JsonObjectBuilder()
        tool_obj.add_string("type", "function")
        tool_obj.add_raw("function", function_obj.finish())
        arr.add_raw(tool_obj.finish())
    return arr.finish()
