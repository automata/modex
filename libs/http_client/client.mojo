"""HTTP client: high-level API for making HTTP/1.1 requests."""

from .net import TcpSocket, resolve_host
from .response import HttpResponse, parse_response


fn _parse_url(
    url: String,
    mut host: String,
    mut port: String,
    mut path: String,
) raises:
    """Parse 'http://host[:port]/path' into components."""
    var rest: String

    # Strip scheme
    if url.startswith("http://"):
        rest = String(url[7:])
    elif url.startswith("https://"):
        raise Error("HTTPS not supported (no TLS). Use http://")
    else:
        raise Error("URL must start with http://")

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
        port = "80"


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

    fn post(
        self,
        url: String,
        body: String = "",
        content_type: String = "application/json",
    ) raises -> HttpResponse:
        """Perform an HTTP POST request."""
        return self.request("POST", url, body, content_type)

    fn request(
        self,
        method: String,
        url: String,
        body: String = "",
        content_type: String = "",
    ) raises -> HttpResponse:
        """Perform an HTTP request."""
        var host = String()
        var port = String()
        var path = String()
        _parse_url(url, host, port, path)

        # Resolve & connect
        var addr = resolve_host(host, port)
        var sock = TcpSocket()
        sock.connect(addr)

        # Build request
        var req = method + " " + path + " HTTP/1.1\r\n"
        req += "Host: " + host + "\r\n"
        req += "Connection: close\r\n"
        req += "User-Agent: " + self.user_agent + "\r\n"

        if len(body) > 0:
            req += "Content-Length: " + String(len(body)) + "\r\n"
            if len(content_type) > 0:
                req += "Content-Type: " + content_type + "\r\n"

        req += "\r\n"
        if len(body) > 0:
            req += body

        # Send & receive
        _ = sock.send_all(req)
        var raw = sock.recv_all()
        sock.close()

        return parse_response(raw)
