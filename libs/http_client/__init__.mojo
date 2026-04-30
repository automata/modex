"""Minimal HTTP/1.1 client over libc sockets.

Uses FFI to libc for DNS resolution, TCP sockets,
and HTTP/1.1 request/response handling.

Example:
    from http_client import HttpClient, HttpResponse

    fn main() raises:
        var client = HttpClient()
        var response = client.get("http://example.com/")
        print(response.status_code)
        print(response.body)
"""

from .chunked import ChunkedStreamDecoder, decode_chunked_body
from .client import HttpClient, HttpHeader
from .response import HttpResponse
