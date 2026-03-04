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
    private var reconnectTask: Task<Void, Never>?
    private var pendingMetadata: ICYMetadata?
    private var networkConditionMonitor: NetworkConditionMonitor?
    private var abrRelayTask: Task<Void, Never>?
    private var recorder: StreamRecorder?

    /// The connection monitor for advanced statistics access.
    public let monitor: ConnectionMonitor

    /// Stream of connection events (connect, disconnect, reconnect, errors, metadata, stats).
    public nonisolated var events: AsyncStream<ConnectionEvent> { monitor.events }

    /// Current connection state.
    public var state: ConnectionState { currentState }

    /// Whether the client is connected (in `.connected` or `.streaming` state).
    public var isConnected: Bool { currentState.isActive }

    /// Current connection statistics.
    public var statistics: ConnectionStatistics {
        get async { await monitor.statistics }
    }

    /// Current connection quality snapshot computed from latest statistics.
    ///
    /// Returns `nil` if not connected or no statistics are available yet.
    public var connectionQuality: ConnectionQuality? {
        get async {
            guard isConnected else { return nil }
            let stats = await monitor.statistics
            return ConnectionQuality.from(statistics: stats)
        }
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
        self.monitor = ConnectionMonitor()
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
        self.monitor = ConnectionMonitor()
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
                await monitor.emit(.error(icecastError))
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
        await monitor.markConnected()
        await emitConnectedEvents(port: port, mode: mode)
        startABRIfConfigured()
        await startRecordingIfConfigured()
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

        let startTime = Date()
        do {
            try await transport.send(data)
            let writeDuration = Date().timeIntervalSince(startTime)
            await monitor.recordBytesSent(data.count)
            await monitor.recordSendLatency(writeDuration * 1000.0)
            await networkConditionMonitor?.recordWrite(
                duration: writeDuration, bytesWritten: data.count
            )
            await writeToRecorder(data)
        } catch {
            await monitor.recordSendError()
            await networkConditionMonitor?.recordWriteFailure()
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
                await monitor.recordMetadataUpdate()
                await monitor.emit(.metadataUpdated(metadata, method: .adminAPI))
                return
            } catch IcecastError.adminAPIUnavailable {
                // Fall through to inline
            }
        }

        pendingMetadata = metadata
        await monitor.recordMetadataUpdate()
        await monitor.emit(.metadataUpdated(metadata, method: .inline))
    }

    /// Disconnects from the server.
    ///
    /// Closes the transport connection, cancels any reconnection attempts,
    /// transitions to `.disconnected`, and emits `.disconnected` event.
    /// Safe to call in any state (idempotent).
    public func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        stopABR()
        await stopRecorderIfActive()

        if let transport = connection {
            await transport.close()
            connection = nil
        }

        negotiatedProtocol = nil
        pendingMetadata = nil

        let wasDisconnected = currentState == .disconnected
        currentState = .disconnected
        await monitor.markDisconnected()

        if !wasDisconnected {
            await monitor.emit(.disconnected(reason: .requested))
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
                await monitor.emit(.error(icecastError))
            }
            throw icecastError
        }
    }

    /// Emits connected and protocol-negotiated events.
    private func emitConnectedEvents(port: Int, mode: ProtocolMode) async {
        await monitor.emit(
            .connected(
                host: configuration.host,
                port: port,
                mountpoint: configuration.mountpoint,
                protocolName: protocolDescription(mode)
            ))
        await monitor.emit(.protocolNegotiated(mode))
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
            await monitor.emit(.disconnected(reason: disconnectReason(for: icecastError)))
            return
        }

        guard reconnectPolicy.isEnabled else {
            currentState = .failed(icecastError)
            await monitor.emit(.disconnected(reason: .networkError("\(error)")))
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
            await monitor.emit(.reconnecting(attempt: attempt, delay: delay))

            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            do {
                try await performReconnection()
                await monitor.recordReconnection()
                return
            } catch {
                currentError = mapToIcecastError(error)
                attempt += 1
            }
        }

        currentState = .failed(currentError)
        await monitor.emit(.disconnected(reason: .maxRetriesExceeded))
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
        await monitor.markConnected()
        await emitConnectedEvents(port: port, mode: mode)
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

    // MARK: - Adaptive Bitrate

    /// Starts the ABR monitor and relay task if configured.
    private func startABRIfConfigured() {
        guard let policy = configuration.adaptiveBitrate else { return }

        let initialBitrate = configuration.stationInfo.bitrate.map { $0 * 1000 } ?? 128_000
        let abrMonitor = NetworkConditionMonitor(
            policy: policy, currentBitrate: initialBitrate
        )
        self.networkConditionMonitor = abrMonitor

        Task { await abrMonitor.start() }

        abrRelayTask = Task { [weak self] in
            for await recommendation in abrMonitor.recommendations {
                guard let self, !Task.isCancelled else { return }
                await self.monitor.emit(.bitrateRecommendation(recommendation))
            }
        }
    }

    /// Stops the ABR monitor and relay task.
    private func stopABR() {
        abrRelayTask?.cancel()
        abrRelayTask = nil
        if let abrMonitor = networkConditionMonitor {
            Task { await abrMonitor.stop() }
        }
        networkConditionMonitor = nil
    }

}

// MARK: - Recording

extension IcecastClient {

    /// Starts recording to the given directory.
    ///
    /// Creates a ``StreamRecorder`` with a ``RecordingConfiguration``
    /// using the client's content type and starts recording immediately.
    ///
    /// - Parameters:
    ///   - directory: Output directory path.
    ///   - contentType: Audio content type. Defaults to the configuration's content type.
    /// - Throws: ``IcecastError/recordingFailed(reason:)`` if already recording,
    ///   or ``IcecastError/recordingDirectoryNotWritable(path:)`` if the directory
    ///   cannot be created.
    public func startRecording(
        directory: String,
        contentType: AudioContentType? = nil
    ) async throws {
        let recordConfig = RecordingConfiguration(
            directory: directory,
            contentType: contentType ?? configuration.contentType
        )
        let newRecorder = StreamRecorder(configuration: recordConfig)
        try await newRecorder.start(mountpoint: configuration.mountpoint)
        recorder = newRecorder
        if let path = await newRecorder.currentFilePath {
            await monitor.emit(.recordingStarted(path: path))
        }
    }

    /// Stops recording and returns final statistics.
    ///
    /// - Returns: Final recording statistics.
    /// - Throws: ``IcecastError/recordingFailed(reason:)`` if an I/O error occurs.
    @discardableResult
    public func stopRecording() async throws -> RecordingStatistics {
        guard let activeRecorder = recorder else {
            return RecordingStatistics(
                duration: 0,
                bytesWritten: 0,
                filesCreated: 0,
                currentFilePath: nil,
                isRecording: false
            )
        }
        let stats = try await activeRecorder.stop()
        recorder = nil
        await monitor.emit(.recordingStopped(statistics: stats))
        return stats
    }

    /// Current recording statistics. `nil` if not recording.
    public var recordingStatistics: RecordingStatistics? {
        get async {
            guard let activeRecorder = recorder else { return nil }
            let stats = await activeRecorder.statistics
            return stats.isRecording ? stats : nil
        }
    }

    /// Starts recording automatically if configuration includes recording settings.
    func startRecordingIfConfigured() async {
        guard let recordConfig = configuration.recording else { return }
        let newRecorder = StreamRecorder(configuration: recordConfig)
        do {
            try await newRecorder.start(mountpoint: configuration.mountpoint)
            recorder = newRecorder
            if let path = await newRecorder.currentFilePath {
                await monitor.emit(.recordingStarted(path: path))
            }
        } catch {
            await monitor.emit(
                .recordingError(mapToIcecastError(error))
            )
        }
    }

    /// Stops the recorder if active, emitting appropriate events.
    func stopRecorderIfActive() async {
        guard let activeRecorder = recorder else { return }
        do {
            let stats = try await activeRecorder.stop()
            recorder = nil
            await monitor.emit(.recordingStopped(statistics: stats))
        } catch {
            recorder = nil
            await monitor.emit(
                .recordingError(mapToIcecastError(error))
            )
        }
    }

    /// Writes data to the recorder, handling rotation events.
    func writeToRecorder(_ data: Data) async {
        guard let activeRecorder = recorder else { return }
        let pathBefore = await activeRecorder.currentFilePath
        do {
            try await activeRecorder.write(data)
            let pathAfter = await activeRecorder.currentFilePath
            if let newPath = pathAfter, newPath != pathBefore {
                await monitor.emit(.recordingFileRotated(newPath: newPath))
            }
        } catch {
            await monitor.emit(
                .recordingError(mapToIcecastError(error))
            )
        }
    }
}
