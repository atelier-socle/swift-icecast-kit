// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

#if canImport(Network)
    import Foundation
    import Network

    /// TCP transport connection using Apple's Network.framework.
    ///
    /// This implementation uses `NWConnection` for reliable TCP communication
    /// on Apple platforms (macOS, iOS, tvOS, watchOS, visionOS).
    /// Thread safety is guaranteed by the actor isolation.
    public actor NWTransportConnection: TransportConnection {

        /// The underlying Network.framework connection.
        private var connection: NWConnection?

        /// Dedicated dispatch queue for NWConnection callbacks.
        private let queue = DispatchQueue(label: "com.ateliersocle.icecastkit.transport")

        /// Tracks the current connection state.
        private var connected: Bool = false

        /// Creates a new transport connection.
        public init() {}

        public var isConnected: Bool {
            connected
        }

        public func connect(host: String, port: Int, useTLS: Bool) async throws {
            guard !connected else {
                throw IcecastError.alreadyConnected
            }

            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))

            let parameters: NWParameters
            if useTLS {
                let tlsOptions = NWProtocolTLS.Options()
                parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
            } else {
                parameters = NWParameters.tcp
            }

            let nwConnection = NWConnection(host: nwHost, port: nwPort, using: parameters)
            self.connection = nwConnection

            let stateStream = AsyncStream<NWConnection.State> { continuation in
                nwConnection.stateUpdateHandler = { state in
                    continuation.yield(state)
                }
                nwConnection.start(queue: self.queue)
            }

            for await state in stateStream {
                switch state {
                case .ready:
                    connected = true
                    return
                case .failed(let error):
                    connected = false
                    throw IcecastError.connectionFailed(
                        host: host, port: port, reason: error.localizedDescription
                    )
                case .cancelled:
                    connected = false
                    throw IcecastError.connectionFailed(
                        host: host, port: port, reason: "Connection cancelled"
                    )
                case .waiting(let error):
                    connected = false
                    throw IcecastError.connectionFailed(
                        host: host, port: port, reason: "Waiting: \(error.localizedDescription)"
                    )
                default:
                    continue
                }
            }
        }

        public func send(_ data: Data) async throws {
            guard let connection, connected else {
                throw IcecastError.notConnected
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(
                    content: data,
                    completion: .contentProcessed { error in
                        if let error {
                            continuation.resume(throwing: IcecastError.sendFailed(reason: error.localizedDescription))
                        } else {
                            continuation.resume()
                        }
                    })
            }
        }

        public func receive(maxBytes: Int) async throws -> Data {
            guard let connection, connected else {
                throw IcecastError.notConnected
            }

            return try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: maxBytes) { content, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: IcecastError.connectionLost(reason: error.localizedDescription))
                    } else if let content, !content.isEmpty {
                        continuation.resume(returning: content)
                    } else if isComplete {
                        continuation.resume(throwing: IcecastError.connectionLost(reason: "Connection closed by peer"))
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }
        }

        public func receive(maxBytes: Int, timeout: TimeInterval) async throws -> Data {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await self.receive(maxBytes: maxBytes)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw IcecastError.connectionTimeout(seconds: timeout)
                }

                guard let result = try await group.next() else {
                    throw IcecastError.connectionTimeout(seconds: timeout)
                }
                group.cancelAll()
                return result
            }
        }

        public func close() async {
            connection?.cancel()
            connection = nil
            connected = false
        }

        /// Updates the connected state.
        private func setConnected(_ value: Bool) {
            connected = value
        }
    }
#endif
