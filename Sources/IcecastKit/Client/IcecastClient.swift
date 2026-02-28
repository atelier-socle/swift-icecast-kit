// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Main client for streaming audio to Icecast/SHOUTcast servers.
///
/// Provides the complete lifecycle: connect → authenticate → stream → metadata → disconnect.
/// Supports automatic reconnection with configurable exponential backoff.
///
/// Usage:
/// ```swift
/// let client = IcecastClient(
///     configuration: IcecastConfiguration(host: "radio.example.com", mountpoint: "/live.mp3"),
///     credentials: IcecastCredentials(password: "hackme")
/// )
/// try await client.connect()
/// try await client.send(audioData)
/// try await client.updateMetadata(ICYMetadata(streamTitle: "Artist - Song"))
/// await client.disconnect()
/// ```
public actor IcecastClient {

    // MARK: - Properties

    private var configuration: IcecastConfiguration
    private var credentials: IcecastCredentials
    private var reconnectPolicy: ReconnectPolicy
    private var currentState: ConnectionState = .disconnected
    private var connection: (any TransportConnection)?
    private var negotiatedProtocol: ProtocolMode?
    private let connectionFactory: @Sendable () -> any TransportConnection
    private let eventContinuation: AsyncStream<ConnectionEvent>.Continuation
    private var _statistics = ConnectionStatistics()
    private var reconnectTask: Task<Void, Never>?
    private var pendingMetadata: ICYMetadata?

    /// Stream of connection events (connect, disconnect, reconnect, errors, metadata, stats).
    public nonisolated let events: AsyncStream<ConnectionEvent>

    /// Current connection state.
    public var state: ConnectionState { currentState }

    /// Whether the client is connected (in `.connected` or `.streaming` state).
    public var isConnected: Bool { currentState.isActive }

    /// Current connection statistics.
    public var statistics: ConnectionStatistics {
        var stats = _statistics
        if let since = stats.connectedSince {
            stats.duration = Date().timeIntervalSince(since)
            if stats.duration > 0 {
                stats.averageBitrate = Double(stats.bytesSent) * 8.0 / stats.duration
            }
        }
        return stats
    }

    // MARK: - Initialization

    /// Creates a new Icecast client.
    ///
    /// - Parameters:
    ///   - configuration: The server and stream configuration.
    ///   - credentials: The authentication credentials.
    ///   - reconnectPolicy: The reconnection policy. Defaults to `.default`.
    public init(
        configuration: IcecastConfiguration,
        credentials: IcecastCredentials,
        reconnectPolicy: ReconnectPolicy = .default
    ) {
        self.configuration = configuration
        self.credentials = credentials
        self.reconnectPolicy = reconnectPolicy
        self.connectionFactory = TransportConnectionFactory.makeConnection
        let (stream, continuation) = AsyncStream<ConnectionEvent>.makeStream()
        self.events = stream
        self.eventContinuation = continuation
    }

    /// Creates a new Icecast client with a custom connection factory.
    ///
    /// - Parameters:
    ///   - configuration: The server and stream configuration.
    ///   - credentials: The authentication credentials.
    ///   - reconnectPolicy: The reconnection policy. Defaults to `.default`.
    ///   - connectionFactory: A factory closure for creating transport connections.
    init(
        configuration: IcecastConfiguration,
        credentials: IcecastCredentials,
        reconnectPolicy: ReconnectPolicy = .default,
        connectionFactory: @Sendable @escaping () -> any TransportConnection
    ) {
        self.configuration = configuration
        self.credentials = credentials
        self.reconnectPolicy = reconnectPolicy
        self.connectionFactory = connectionFactory
        let (stream, continuation) = AsyncStream<ConnectionEvent>.makeStream()
        self.events = stream
        self.eventContinuation = continuation
    }

    // MARK: - Connection Lifecycle

    /// Connects to the server.
    ///
    /// Sequence:
    /// 1. Create transport connection
    /// 2. Connect TCP to host:port
    /// 3. Negotiate protocol (PUT/SOURCE/SHOUTcast) via ``ProtocolNegotiator``
    /// 4. State transitions: disconnected → connecting → authenticating → connected
    /// 5. Emit `.connected` and `.protocolNegotiated` events
    ///
    /// - Throws: ``IcecastError/alreadyConnected`` if already connected,
    ///   or another ``IcecastError`` if connection or authentication fails.
    public func connect() async throws {
        switch currentState {
        case .disconnected, .failed: break
        default: throw IcecastError.alreadyConnected
        }

        currentState = .connecting
        let transport = connectionFactory()
        let port = effectivePort()

        do {
            try await transport.connect(host: configuration.host, port: port, useTLS: configuration.useTLS)
        } catch {
            let icecastError = mapToIcecastError(error)
            if currentState == .connecting {
                currentState = .failed(icecastError)
                eventContinuation.yield(.error(icecastError))
            }
            throw icecastError
        }

        guard currentState == .connecting else {
            await transport.close()
            throw IcecastError.notConnected
        }
        currentState = .authenticating

        let negotiator = ProtocolNegotiator(connectionFactory: connectionFactory)
        let mode = try await negotiateOrFail(negotiator: negotiator, transport: transport)

        guard currentState == .authenticating else {
            await transport.close()
            if let fallback = await negotiator.fallbackConnection {
                await fallback.close()
            }
            throw IcecastError.notConnected
        }

        if let fallback = await negotiator.fallbackConnection {
            self.connection = fallback
        } else {
            self.connection = transport
        }
        self.negotiatedProtocol = mode
        currentState = .connected
        _statistics.connectedSince = Date()
        emitConnectedEvents(port: port, mode: mode)
    }

    /// Sends audio data to the server.
    ///
    /// On first call, transitions state from `.connected` to `.streaming`.
    /// If connection is lost during send and reconnection is enabled,
    /// enters the reconnection loop.
    ///
    /// - Parameter data: The audio data to send.
    /// - Throws: ``IcecastError/notConnected`` if not in a sendable state.
    public func send(_ data: Data) async throws {
        guard currentState.canSend else {
            throw IcecastError.notConnected
        }
        guard let transport = connection else {
            throw IcecastError.notConnected
        }

        if currentState == .connected {
            currentState = .streaming
        }

        do {
            try await transport.send(data)
            _statistics.bytesSent += UInt64(data.count)
            _statistics.bytesTotal += UInt64(data.count)
        } catch {
            _statistics.sendErrorCount += 1
            await handleConnectionLoss(error: error)
            throw mapToIcecastError(error)
        }
    }

    /// Updates stream metadata.
    ///
    /// If admin credentials are configured, uses the admin API (preferred).
    /// Otherwise stores metadata for inline interleaving.
    /// Emits `.metadataUpdated` event on success.
    ///
    /// - Parameter metadata: The metadata to update.
    /// - Throws: ``IcecastError/notConnected`` if not connected.
    public func updateMetadata(_ metadata: ICYMetadata) async throws {
        guard currentState.isActive else {
            throw IcecastError.notConnected
        }

        if let adminCredentials = configuration.adminCredentials {
            let adminClient = AdminMetadataClient(
                host: configuration.host,
                port: configuration.port,
                useTLS: configuration.useTLS,
                credentials: adminCredentials,
                connectionFactory: connectionFactory
            )
            do {
                try await adminClient.updateMetadata(metadata, mountpoint: configuration.mountpoint)
                _statistics.metadataUpdateCount += 1
                eventContinuation.yield(.metadataUpdated(metadata, method: .adminAPI))
                return
            } catch IcecastError.adminAPIUnavailable {
                // Fall through to inline
            }
        }

        pendingMetadata = metadata
        _statistics.metadataUpdateCount += 1
        eventContinuation.yield(.metadataUpdated(metadata, method: .inline))
    }

    /// Disconnects from the server.
    ///
    /// Closes the transport connection, cancels any reconnection attempts,
    /// transitions to `.disconnected`, and emits `.disconnected` event.
    /// Safe to call in any state (idempotent).
    public func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil

        if let transport = connection {
            await transport.close()
            connection = nil
        }

        negotiatedProtocol = nil
        pendingMetadata = nil
        _statistics.connectedSince = nil

        let wasDisconnected = currentState == .disconnected
        currentState = .disconnected

        if !wasDisconnected {
            eventContinuation.yield(.disconnected(reason: .requested))
        }
    }

    /// Updates the configuration for the next connection attempt.
    ///
    /// - Parameter configuration: The new configuration.
    public func updateConfiguration(_ configuration: IcecastConfiguration) {
        self.configuration = configuration
    }

    /// Updates the reconnection policy.
    ///
    /// Takes effect immediately for any in-progress reconnection loop.
    ///
    /// - Parameter policy: The new reconnection policy.
    public func updateReconnectPolicy(_ policy: ReconnectPolicy) {
        self.reconnectPolicy = policy
    }

    // MARK: - Private Helpers

    /// Calculates the effective port, adjusting for SHOUTcast source connections.
    private func effectivePort() -> Int {
        switch configuration.protocolMode {
        case .shoutcastV1, .shoutcastV2:
            return ShoutcastProtocol().sourcePort(forListenerPort: configuration.port)
        default:
            return configuration.port
        }
    }

    /// Negotiates the protocol or transitions to failed state on error.
    private func negotiateOrFail(
        negotiator: ProtocolNegotiator,
        transport: any TransportConnection
    ) async throws -> ProtocolMode {
        do {
            return try await negotiator.negotiate(
                connection: transport,
                configuration: configuration,
                credentials: credentials
            )
        } catch {
            await transport.close()
            let icecastError = mapToIcecastError(error)
            if currentState == .authenticating {
                currentState = .failed(icecastError)
                eventContinuation.yield(.error(icecastError))
            }
            throw icecastError
        }
    }

    /// Emits connected and protocol-negotiated events.
    private func emitConnectedEvents(port: Int, mode: ProtocolMode) {
        eventContinuation.yield(
            .connected(
                host: configuration.host,
                port: port,
                mountpoint: configuration.mountpoint,
                protocolName: protocolDescription(mode)
            ))
        eventContinuation.yield(.protocolNegotiated(mode))
    }

    /// Handles a connection loss by entering reconnection or transitioning to failed.
    private func handleConnectionLoss(error: Error) async {
        if let transport = connection {
            await transport.close()
            connection = nil
        }
        negotiatedProtocol = nil

        let icecastError = mapToIcecastError(error)

        if isNonRecoverableError(icecastError) {
            currentState = .failed(icecastError)
            eventContinuation.yield(.disconnected(reason: disconnectReason(for: icecastError)))
            return
        }

        guard reconnectPolicy.isEnabled else {
            currentState = .failed(icecastError)
            eventContinuation.yield(.disconnected(reason: .networkError("\(error)")))
            return
        }

        startReconnectionLoop(lastError: icecastError)
    }

    /// Starts the reconnection loop as a cancellable task.
    private func startReconnectionLoop(lastError: IcecastError) {
        reconnectTask?.cancel()
        reconnectTask = Task {
            await runReconnectionAttempts(lastError: lastError)
        }
    }

    /// Runs reconnection attempts with exponential backoff.
    private func runReconnectionAttempts(lastError: IcecastError) async {
        var attempt = 0
        var currentError = lastError

        while attempt < reconnectPolicy.maxRetries {
            guard !Task.isCancelled else { return }

            let delay = reconnectPolicy.delay(forAttempt: attempt)
            currentState = .reconnecting(attempt: attempt, nextRetryIn: delay)
            eventContinuation.yield(.reconnecting(attempt: attempt, delay: delay))

            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            do {
                try await performReconnection()
                _statistics.reconnectionCount += 1
                return
            } catch {
                currentError = mapToIcecastError(error)
                attempt += 1
            }
        }

        currentState = .failed(currentError)
        eventContinuation.yield(.disconnected(reason: .maxRetriesExceeded))
    }

    /// Performs a single reconnection attempt.
    private func performReconnection() async throws {
        let transport = connectionFactory()
        let port = effectivePort()

        do {
            try await transport.connect(host: configuration.host, port: port, useTLS: configuration.useTLS)
        } catch {
            await transport.close()
            throw mapToIcecastError(error)
        }

        let negotiator = ProtocolNegotiator(connectionFactory: connectionFactory)
        let mode: ProtocolMode

        do {
            mode = try await negotiator.negotiate(
                connection: transport,
                configuration: configuration,
                credentials: credentials
            )
        } catch {
            await transport.close()
            throw mapToIcecastError(error)
        }

        if let fallback = await negotiator.fallbackConnection {
            self.connection = fallback
        } else {
            self.connection = transport
        }
        self.negotiatedProtocol = mode
        currentState = .connected
        _statistics.connectedSince = Date()
        emitConnectedEvents(port: port, mode: mode)
    }

    /// Maps a generic error to an ``IcecastError``.
    private func mapToIcecastError(_ error: Error) -> IcecastError {
        if let icecastError = error as? IcecastError {
            return icecastError
        }
        return .connectionLost(reason: "\(error)")
    }

    /// Returns whether the given error is non-recoverable (skip reconnection).
    private func isNonRecoverableError(_ error: IcecastError) -> Bool {
        switch error {
        case .authenticationFailed, .mountpointInUse, .contentTypeNotSupported, .credentialsRequired:
            return true
        default:
            return false
        }
    }

    /// Maps an ``IcecastError`` to a ``DisconnectReason``.
    private func disconnectReason(for error: IcecastError) -> DisconnectReason {
        switch error {
        case .authenticationFailed:
            return .authenticationFailed
        case .mountpointInUse:
            return .mountpointInUse
        case .contentTypeNotSupported:
            return .contentTypeRejected
        default:
            return .networkError("\(error)")
        }
    }

    /// Returns a human-readable protocol description.
    private func protocolDescription(_ mode: ProtocolMode) -> String {
        switch mode {
        case .auto: return "auto"
        case .icecastPUT: return "Icecast PUT"
        case .icecastSOURCE: return "Icecast SOURCE"
        case .shoutcastV1: return "SHOUTcast v1"
        case .shoutcastV2: return "SHOUTcast v2"
        }
    }
}
