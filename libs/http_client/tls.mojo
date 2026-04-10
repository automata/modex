"""TLS socket support via OpenSSL libssl/libcrypto FFI.

Uses Mojo's dynamic library loader (`OwnedDLHandle`) to load libssl/libcrypto
at runtime and call OpenSSL symbols via dlsym.
"""

from ffi import OwnedDLHandle, c_int, c_char, c_size_t
from memory import OpaquePointer, alloc

from .net import TcpSocket, sockaddr_in, make_c_str

comptime SSL_VERIFY_PEER: c_int = 1
comptime SSL_ERROR_SSL: c_int = 1
comptime SSL_ERROR_WANT_READ: c_int = 2
comptime SSL_ERROR_WANT_WRITE: c_int = 3
comptime SSL_ERROR_SYSCALL: c_int = 5
comptime SSL_ERROR_ZERO_RETURN: c_int = 6
comptime SSL_CTRL_SET_TLSEXT_HOSTNAME: c_int = 55
comptime TLSEXT_NAMETYPE_HOST_NAME: c_int = 0
comptime X509_V_OK: Int = 0


struct TlsSocket:
    """A simple blocking TLS socket backed by OpenSSL."""

    var tcp: TcpSocket
    var ssl_lib: OwnedDLHandle
    var crypto_lib: OwnedDLHandle
    var ctx: OpaquePointer[MutExternalOrigin]
    var ssl: OpaquePointer[MutExternalOrigin]

    fn __init__(out self) raises:
        self.tcp = TcpSocket()
        self.ssl_lib = OwnedDLHandle("libssl.so.3")
        self.crypto_lib = OwnedDLHandle("libcrypto.so.3")
        self.ctx = OpaquePointer[MutExternalOrigin]()
        self.ssl = OpaquePointer[MutExternalOrigin]()

        var init_ok = self.ssl_lib.call["OPENSSL_init_ssl", c_int](
            c_int(0), OpaquePointer[MutExternalOrigin]()
        )
        if init_ok != 1:
            raise Error("OPENSSL_init_ssl() failed")

        var method = self.ssl_lib.call[
            "TLS_client_method", OpaquePointer[MutExternalOrigin]
        ]()
        if not method:
            raise Error("TLS_client_method() failed")

        self.ctx = self.ssl_lib.call[
            "SSL_CTX_new", OpaquePointer[MutExternalOrigin]
        ](method)
        if not self.ctx:
            raise Error("SSL_CTX_new() failed: " + self.last_error())

        var verify_paths_ok = self.ssl_lib.call[
            "SSL_CTX_set_default_verify_paths", c_int
        ](self.ctx)
        if verify_paths_ok != 1:
            self.close()
            raise Error(
                "SSL_CTX_set_default_verify_paths() failed: "
                + self.last_error()
            )

        self.ssl_lib.call["SSL_CTX_set_verify", NoneType](
            self.ctx,
            SSL_VERIFY_PEER,
            OpaquePointer[MutExternalOrigin](),
        )

    fn connect(mut self, host: String, addr: sockaddr_in) raises:
        """Connect TCP socket and perform TLS handshake with hostname verification."""
        self.tcp.connect(addr)

        self.ssl = self.ssl_lib.call[
            "SSL_new", OpaquePointer[MutExternalOrigin]
        ](self.ctx)
        if not self.ssl:
            self.close()
            raise Error("SSL_new() failed: " + self.last_error())

        var set_fd_ok = self.ssl_lib.call["SSL_set_fd", c_int](
            self.ssl, self.tcp.fd
        )
        if set_fd_ok != 1:
            self.close()
            raise Error("SSL_set_fd() failed: " + self.last_error())

        # Enable certificate hostname verification.
        var c_host = make_c_str(host)
        var set1_host_ok = self.ssl_lib.call["SSL_set1_host", c_int](
            self.ssl, c_host
        )
        c_host.free()
        if set1_host_ok != 1:
            self.close()
            raise Error("SSL_set1_host() failed: " + self.last_error())

        # Set SNI using SSL_ctrl (SSL_set_tlsext_host_name is a macro).
        var c_sni = make_c_str(host)
        var sni_ok = self.ssl_lib.call["SSL_ctrl", Int](
            self.ssl,
            SSL_CTRL_SET_TLSEXT_HOSTNAME,
            Int(TLSEXT_NAMETYPE_HOST_NAME),
            c_sni,
        )
        c_sni.free()
        if sni_ok != 1:
            self.close()
            raise Error("Setting SNI failed: " + self.last_error())

        var connect_ok = self.ssl_lib.call["SSL_connect", c_int](self.ssl)
        if connect_ok != 1:
            var err = self.ssl_lib.call["SSL_get_error", c_int](
                self.ssl, connect_ok
            )
            var message = self.last_error()
            self.close()
            raise Error(
                "SSL_connect() failed (error="
                + String(err)
                + "): "
                + message
            )

        var verify_result = self.ssl_lib.call[
            "SSL_get_verify_result", Int
        ](self.ssl)
        if verify_result != X509_V_OK:
            self.close()
            raise Error(
                "TLS certificate verification failed: code "
                + String(verify_result)
            )

    fn send_all(self, data: String) raises -> Int:
        """Send bytes over TLS. Returns bytes sent."""
        var bytes = data.as_bytes()
        var buf = alloc[UInt8](len(bytes))
        for i in range(len(bytes)):
            buf[i] = bytes[i]

        var sent = self.ssl_lib.call["SSL_write", c_int](
            self.ssl, buf, c_int(len(bytes))
        )
        buf.free()

        if sent <= 0:
            var err = self.ssl_lib.call["SSL_get_error", c_int](self.ssl, sent)
            raise Error(
                "SSL_write() failed (error="
                + String(err)
                + "): "
                + self.last_error()
            )
        return Int(sent)

    fn recv(self, max_bytes: Int = 4096) raises -> String:
        """Receive up to max_bytes from TLS stream. Returns empty string on EOF."""
        var buf = alloc[UInt8](max_bytes)
        var n = self.ssl_lib.call["SSL_read", c_int](
            self.ssl, buf, c_int(max_bytes)
        )

        if n > 0:
            var result = String()
            for i in range(n):
                result += chr(Int(buf[i]))
            buf.free()
            return result

        var err = self.ssl_lib.call["SSL_get_error", c_int](self.ssl, n)
        buf.free()

        if err == SSL_ERROR_ZERO_RETURN:
            return ""
        if err == SSL_ERROR_WANT_READ or err == SSL_ERROR_WANT_WRITE:
            return ""
        if err == SSL_ERROR_SYSCALL:
            return ""

        raise Error(
            "SSL_read() failed (error="
            + String(err)
            + "): "
            + self.last_error()
        )

    fn recv_all(self, max_bytes: Int = 1024 * 64) raises -> String:
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

    fn last_error(self) -> String:
        """Return latest OpenSSL error string, if any."""
        var code = self.crypto_lib.call["ERR_get_error", UInt64]()
        if code == 0:
            return "unknown OpenSSL error"

        var buf = alloc[c_char](256)
        self.crypto_lib.call["ERR_error_string_n", NoneType](
            code, buf, c_size_t(256)
        )
        var msg = String(unsafe_from_utf8_ptr=buf)
        buf.free()
        return msg

    fn close(mut self):
        """Free TLS state and close underlying socket."""
        if self.ssl:
            self.ssl_lib.call["SSL_free", NoneType](self.ssl)
            self.ssl = OpaquePointer[MutExternalOrigin]()
        if self.ctx:
            self.ssl_lib.call["SSL_CTX_free", NoneType](self.ctx)
            self.ctx = OpaquePointer[MutExternalOrigin]()
        self.tcp.close()
