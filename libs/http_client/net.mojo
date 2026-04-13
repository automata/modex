"""Low-level networking: libc socket FFI bindings and helpers."""

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
# Structs
# ===-----------------------------------------------------------------------===#


struct sockaddr_in(ImplicitlyCopyable, Copyable):
    """Linux x86_64 sockaddr_in (16 bytes)."""

    var sin_family: UInt16
    var sin_port: UInt16
    var sin_addr: UInt32
    var _pad0: UInt32
    var _pad1: UInt32

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

    fn ip_string(self) -> String:
        """Return dotted-quad IP string."""
        var a = Int(self.sin_addr)
        return (
            String(a & 0xFF)
            + "."
            + String((a >> 8) & 0xFF)
            + "."
            + String((a >> 16) & 0xFF)
            + "."
            + String((a >> 24) & 0xFF)
        )


struct addrinfo:
    """Linux x86_64 addrinfo."""

    var ai_flags: c_int
    var ai_family: c_int
    var ai_socktype: c_int
    var ai_protocol: c_int
    var ai_addrlen: UInt32
    var _align_pad: UInt32
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


# ===-----------------------------------------------------------------------===#
# DNS
# ===-----------------------------------------------------------------------===#


fn resolve_host(host: String, port: String) raises -> sockaddr_in:
    """Resolve hostname to IPv4 sockaddr_in via getaddrinfo.

    Note: for now we force AF_INET because the current socket layer only
    implements sockaddr_in / IPv4. Hosts like openrouter.ai often resolve to
    IPv6 first, which would otherwise be miscast and cause connect() failures.
    """
    var hints = addrinfo()
    hints.ai_family = AF_INET
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = IPPROTO_TCP

    var res = alloc[UnsafePointer[mut=True, addrinfo, MutExternalOrigin]](1)
    res[0] = UnsafePointer[mut=True, addrinfo, MutExternalOrigin]()

    var c_host = make_c_str(host)
    var c_port = make_c_str(port)

    var ret = external_call["getaddrinfo", c_int](
        c_host, c_port, UnsafePointer(to=hints), res,
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

    var addr = ai[].ai_addr[]
    external_call["freeaddrinfo", NoneType](ai)
    res.free()
    return addr


# ===-----------------------------------------------------------------------===#
# TCP socket
# ===-----------------------------------------------------------------------===#


struct TcpSocket:
    """A simple blocking TCP socket."""

    var fd: c_int

    fn __init__(out self):
        self.fd = -1

    fn connect(mut self, addr: sockaddr_in) raises:
        """Create socket and connect to address."""
        self.fd = external_call["socket", c_int](
            AF_INET, SOCK_STREAM, c_int(0),
        )
        if self.fd < 0:
            raise Error("socket() failed")

        var sa = addr
        var ret = external_call["connect", c_int](
            self.fd, UnsafePointer(to=sa), c_int(16),
        )
        if ret < 0:
            self.close()
            raise Error("connect() failed")

    fn send_all(self, data: String) raises -> Int:
        """Send all bytes. Returns bytes sent."""
        var bytes = data.as_bytes()
        var buf = alloc[UInt8](len(bytes))
        for i in range(len(bytes)):
            buf[i] = bytes[i]

        var sent = external_call["send", Int](
            self.fd, buf, c_size_t(len(bytes)), c_int(0),
        )
        buf.free()

        if sent < 0:
            raise Error("send() failed")
        return sent

    fn recv(self, max_bytes: Int = 4096) -> String:
        """Receive up to max_bytes. Returns empty string on EOF."""
        var buf = alloc[UInt8](max_bytes)
        var n = external_call["recv", Int](
            self.fd, buf, c_size_t(max_bytes), c_int(0),
        )

        var result = String()
        if n > 0:
            for i in range(n):
                result += chr(Int(buf[i]))
        buf.free()
        return result

    fn recv_all(self, max_bytes: Int = 1024 * 64) -> String:
        """Read until EOF or max_bytes."""
        var result = String()
        var total = 0
        while total < max_bytes:
            var chunk = self.recv(min(4096, max_bytes - total))
            if len(chunk) == 0:
                break
            result += chunk
            total += len(chunk)
        return result

    fn close(mut self):
        """Close the socket."""
        if self.fd >= 0:
            _ = external_call["close", c_int](self.fd)
            self.fd = -1
