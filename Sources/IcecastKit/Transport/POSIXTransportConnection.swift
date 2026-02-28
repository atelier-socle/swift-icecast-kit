// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

#if !canImport(Network)
    import Foundation

    #if canImport(Darwin)
        import Darwin
    #elseif canImport(Glibc)
        import Glibc
    #endif

    /// TCP transport connection using POSIX sockets for Linux.
    ///
    /// This implementation uses raw POSIX socket APIs for TCP communication
    /// on platforms where Network.framework is not available.
    /// Thread safety is guaranteed by the actor isolation.
    ///
    /// > Note: TLS is not supported on Linux in version 0.1.0.
    /// > Secure connections require Apple platforms with Network.framework.
    public actor POSIXTransportConnection: TransportConnection {

        /// The file descriptor for the socket.
        private var socketFD: Int32 = -1

        /// Tracks the current connection state.
        private var connected: Bool = false

        /// Creates a new POSIX transport connection.
        public init() {}

        public var isConnected: Bool {
            connected
        }

        public func connect(host: String, port: Int, useTLS: Bool) async throws {
            guard !connected else {
                throw IcecastError.alreadyConnected
            }

            if useTLS {
                throw IcecastError.tlsError(reason: "TLS is not supported on Linux in version 0.1.0")
            }

            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = Int32(SOCK_STREAM)
            hints.ai_protocol = Int32(IPPROTO_TCP)

            var result: UnsafeMutablePointer<addrinfo>?
            let portString = String(port)
            let status = getaddrinfo(host, portString, &hints, &result)

            guard status == 0, let addrList = result else {
                throw IcecastError.dnsResolutionFailed(host: host)
            }
            defer { freeaddrinfo(addrList) }

            var lastError: String = "Unknown error"
            var currentAddr: UnsafeMutablePointer<addrinfo>? = addrList

            while let addr = currentAddr {
                let fd = socket(addr.pointee.ai_family, addr.pointee.ai_socktype, addr.pointee.ai_protocol)
                guard fd >= 0 else {
                    currentAddr = addr.pointee.ai_next
                    continue
                }

                #if canImport(Darwin)
                    let connectResult = Darwin.connect(fd, addr.pointee.ai_addr, addr.pointee.ai_addrlen)
                #elseif canImport(Glibc)
                    let connectResult = Glibc.connect(fd, addr.pointee.ai_addr, addr.pointee.ai_addrlen)
                #endif

                if connectResult == 0 {
                    socketFD = fd
                    connected = true
                    return
                }

                lastError = String(cString: strerror(errno))
                #if canImport(Darwin)
                    Darwin.close(fd)
                #elseif canImport(Glibc)
                    Glibc.close(fd)
                #endif
                currentAddr = addr.pointee.ai_next
            }

            throw IcecastError.connectionFailed(host: host, port: port, reason: lastError)
        }

        public func send(_ data: Data) async throws {
            guard connected, socketFD >= 0 else {
                throw IcecastError.notConnected
            }

            try data.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    throw IcecastError.sendFailed(reason: "Empty data buffer")
                }
                var totalSent = 0
                let count = buffer.count
                while totalSent < count {
                    #if canImport(Darwin)
                        let sent = Darwin.send(socketFD, baseAddress.advanced(by: totalSent), count - totalSent, 0)
                    #elseif canImport(Glibc)
                        let sent = Glibc.send(socketFD, baseAddress.advanced(by: totalSent), count - totalSent, 0)
                    #endif

                    guard sent > 0 else {
                        throw IcecastError.sendFailed(reason: "send() returned \(sent): \(String(cString: strerror(errno)))")
                    }
                    totalSent += sent
                }
            }
        }

        public func receive(maxBytes: Int) async throws -> Data {
            guard connected, socketFD >= 0 else {
                throw IcecastError.notConnected
            }

            var buffer = [UInt8](repeating: 0, count: maxBytes)
            #if canImport(Darwin)
                let bytesRead = Darwin.recv(socketFD, &buffer, maxBytes, 0)
            #elseif canImport(Glibc)
                let bytesRead = Glibc.recv(socketFD, &buffer, maxBytes, 0)
            #endif

            guard bytesRead > 0 else {
                if bytesRead == 0 {
                    throw IcecastError.connectionLost(reason: "Connection closed by peer")
                }
                throw IcecastError.connectionLost(reason: "recv() error: \(String(cString: strerror(errno)))")
            }

            return Data(buffer[0..<bytesRead])
        }

        public func receive(maxBytes: Int, timeout: TimeInterval) async throws -> Data {
            guard connected, socketFD >= 0 else {
                throw IcecastError.notConnected
            }

            var pollFD = pollfd()
            pollFD.fd = socketFD
            pollFD.events = Int16(POLLIN)

            let timeoutMs = Int32(timeout * 1000)
            let pollResult = poll(&pollFD, 1, timeoutMs)

            guard pollResult > 0 else {
                if pollResult == 0 {
                    throw IcecastError.connectionTimeout(seconds: timeout)
                }
                throw IcecastError.connectionLost(reason: "poll() error: \(String(cString: strerror(errno)))")
            }

            return try await receive(maxBytes: maxBytes)
        }

        public func close() async {
            guard socketFD >= 0 else { return }
            #if canImport(Darwin)
                Darwin.close(socketFD)
            #elseif canImport(Glibc)
                Glibc.close(socketFD)
            #endif
            socketFD = -1
            connected = false
        }
    }
#endif
