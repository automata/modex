"""Experiment: Minimal native HTTP/1.1 client over libc sockets.

Uses FFI to libc for socket(), connect(), send(), recv(), getaddrinfo().
No Python interop — pure Mojo + libc.

Note: This is plain HTTP (no TLS). For HTTPS, we'd need to link against
OpenSSL/libssl via FFI or use Python interop. For the experiment, we
query http://void.cc on port 80 which returns a 301 redirect to HTTPS.
"""

from ffi import external_call, c_int, c_char, c_size_t
from memory import UnsafePointer, alloc

# ===-----------------------------------------------------------------------===#
# Constants
# ===-----------------------------------------------------------------------===#

comptime AF_INET: c_int = 2
comptime AF_UNSPEC: c_int = 0
comptime SOCK_STREAM: c_int = 1
comptime IPPROTO_TCP: c_int = 6


# ===-----------------------------------------------------------------------===#
# Structs for libc networking (Linux x86_64 layout)
# ===-----------------------------------------------------------------------===#


struct sockaddr_in(ImplicitlyCopyable, Copyable):
    """Sockaddr_in: 16 bytes on Linux x86_64."""
    var sin_family: UInt16
    var sin_port: UInt16  # network byte order (big-endian)
    var sin_addr: UInt32  # network byte order
    var _pad0: UInt32     # sin_zero[0:4]
    var _pad1: UInt32     # sin_zero[4:8]

    fn __init__(out self):
        self.sin_family = 0
        self.sin_port = 0
        self.sin_addr = 0
        self._pad0 = 0
        self._pad1 = 0

    fn __copyinit__(out self, copy: Self):
        self.sin_family = copy.sin_family
        self.sin_port = copy.sin_port
        self.sin_addr = copy.sin_addr
        self._pad0 = copy._pad0
        self._pad1 = copy._pad1


struct addrinfo:
    """Addrinfo: matches Linux x86_64 layout."""
    var ai_flags: c_int
    var ai_family: c_int
    var ai_socktype: c_int
    var ai_protocol: c_int
    var ai_addrlen: UInt32
    var _align_pad: UInt32  # padding for 8-byte alignment
    var ai_addr: UnsafePointer[mut=True, sockaddr_in, MutExternalOrigin]
    var ai_canonname: UnsafePointer[mut=True, c_char, MutExternalOrigin]
    var ai_next: UnsafePointer[mut=True, addrinfo, MutExternalOrigin]

    fn __init__(out self):
        self.ai_flags = 0
        self.ai_family = 0
        self.ai_socktype = 0
        self.ai_protocol = 0
        self.ai_addrlen = 0
        self._align_pad = 0
        self.ai_addr = UnsafePointer[mut=True, sockaddr_in, MutExternalOrigin]()
        self.ai_canonname = UnsafePointer[mut=True, c_char, MutExternalOrigin]()
        self.ai_next = UnsafePointer[mut=True, addrinfo, MutExternalOrigin]()


# ===-----------------------------------------------------------------------===#
# Helpers
# ===-----------------------------------------------------------------------===#


fn make_c_str(s: String) -> UnsafePointer[mut=True, c_char, MutExternalOrigin]:
    """Allocate a null-terminated C string. Caller must free."""
    var n = len(s)
    var ptr = alloc[c_char](n + 1)
    var bytes = s.as_bytes()
    for i in range(n):
        ptr[i] = bytes[i].cast[DType.int8]()
    ptr[n] = 0
    return ptr


fn recv_all(fd: c_int, max_bytes: Int = 1024 * 64) -> String:
    """Read from socket until EOF or max_bytes."""
    var buf = alloc[UInt8](4096)
    var result = String()
    var total = 0

    while total < max_bytes:
        var n = external_call["recv", Int](fd, buf, c_size_t(4096), c_int(0))
        if n <= 0:
            break
        for i in range(n):
            result += chr(Int(buf[i]))
        total += n

    buf.free()
    return result


# ===-----------------------------------------------------------------------===#
# DNS resolution
# ===-----------------------------------------------------------------------===#


fn resolve_host(host: String, port: String) raises -> sockaddr_in:
    """Resolve hostname to sockaddr_in via getaddrinfo."""
    var hints = addrinfo()
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = IPPROTO_TCP

    # Pointer-to-pointer for getaddrinfo result
    var res = alloc[UnsafePointer[mut=True, addrinfo, MutExternalOrigin]](1)
    res[0] = UnsafePointer[mut=True, addrinfo, MutExternalOrigin]()

    var c_host = make_c_str(host)
    var c_port = make_c_str(port)

    var ret = external_call["getaddrinfo", c_int](
        c_host,
        c_port,
        UnsafePointer(to=hints),
        res,
    )

    c_host.free()
    c_port.free()

    if ret != 0:
        res.free()
        raise Error("getaddrinfo failed with code: " + String(ret))

    var ai = res[0]
    if not ai:
        res.free()
        raise Error("getaddrinfo returned no results")

    # Copy the first result's sockaddr_in
    var addr = ai[].ai_addr[]

    external_call["freeaddrinfo", NoneType](ai)
    res.free()

    return addr


# ===-----------------------------------------------------------------------===#
# Main
# ===-----------------------------------------------------------------------===#


fn main() raises:
    var host = "void.cc"
    var port = "80"
    var path = "/"

    print("=== Native Mojo HTTP/1.1 Client ===")
    print()

    # --- DNS ---
    print("Resolving", host, "...")
    var addr = resolve_host(host, port)

    var a = Int(addr.sin_addr)
    print(
        "Resolved to: ",
        a & 0xFF, ".",
        (a >> 8) & 0xFF, ".",
        (a >> 16) & 0xFF, ".",
        (a >> 24) & 0xFF,
        sep="",
    )

    # --- Socket ---
    var fd = external_call["socket", c_int](AF_INET, SOCK_STREAM, c_int(0))
    if fd < 0:
        raise Error("socket() failed")
    print("Socket fd:", fd)

    # --- Connect ---
    print("Connecting to " + host + ":" + port + " ...")
    var connect_ret = external_call["connect", c_int](
        fd,
        UnsafePointer(to=addr),
        c_int(16),
    )
    if connect_ret < 0:
        _ = external_call["close", c_int](fd)
        raise Error("connect() failed")
    print("Connected!")
    print()

    # --- HTTP request ---
    var request = String(
        "GET " + path + " HTTP/1.1\r\n"
        + "Host: " + host + "\r\n"
        + "Connection: close\r\n"
        + "User-Agent: modex/0.1 (Mojo)\r\n"
        + "\r\n"
    )

    print(">>> Request:")
    print(request)

    var req_bytes = request.as_bytes()
    var send_buf = alloc[UInt8](len(req_bytes))
    for i in range(len(req_bytes)):
        send_buf[i] = req_bytes[i]

    var sent = external_call["send", Int](
        fd, send_buf, c_size_t(len(req_bytes)), c_int(0)
    )
    send_buf.free()

    if sent < 0:
        _ = external_call["close", c_int](fd)
        raise Error("send() failed")
    print("Sent", sent, "bytes")
    print()

    # --- Response ---
    print("<<< Response:")
    print("---")
    var response = recv_all(fd)
    print(response)
    print("---")
    print("Received", len(response), "bytes total")

    # --- Cleanup ---
    _ = external_call["close", c_int](fd)
    print("Connection closed.")
