// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Events emitted by ``IcecastRelay`` during its lifecycle.
public enum RelayEvent: Sendable {
    /// Successfully connected to the source stream.
    case connected(serverVersion: String?, contentType: AudioContentType?)

    /// Disconnected from the source stream.
    case disconnected(error: IcecastError?)

    /// Attempting to reconnect to the source stream.
    case reconnecting(attempt: Int)

    /// Successfully reconnected after a connection loss.
    case reconnected

    /// ICY metadata was updated in the stream.
    case metadataUpdated(ICYMetadata)

    /// The source stream ended cleanly (server closed the connection).
    case streamEnded
}

/// Receives audio from a remote Icecast or SHOUTcast stream as a listener.
///
/// `IcecastRelay` connects to a source stream via HTTP GET, demultiplexes
/// audio data from ICY metadata, and emits ``AudioChunk`` values through
/// an ``audioStream``. Supports automatic reconnection and can be paired
/// with ``StreamRecorder`` for recording or ``IcecastClient`` for
/// re-broadcasting.
///
/// Usage:
/// ```swift
/// let config = IcecastRelayConfiguration(
///     sourceURL: "https://radio.example.com:8000/live.mp3"
/// )
/// let relay = IcecastRelay(configuration: config)
/// try await relay.connect()
///
/// for await chunk in relay.audioStream {
///     // Process audio data
/// }
/// ```
public actor IcecastRelay {

    // MARK: - Properties

    private let configuration: IcecastRelayConfiguration
    private let transportFactory: @Sendable () -> any TransportConnection
    private var httpClient: ListenerHTTPClient?
    private var readTask: Task<Void, Never>?
    private var connected: Bool = false
    private var metadata: ICYMetadata?
    private var contentType: AudioContentType?
    private var totalBytesReceived: Int64 = 0
    private var server: String?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?
    private var eventContinuation: AsyncStream<RelayEvent>.Continuation?
    private let audioStreamStorage: AsyncStream<AudioChunk>
    private let eventStreamStorage: AsyncStream<RelayEvent>

    // MARK: - Initialization

    /// Creates an Icecast relay with the given configuration.
    ///
    /// - Parameter configuration: The relay configuration.
    public init(configuration: IcecastRelayConfiguration) {
        self.init(
            configuration: configuration,
            transportFactory: { TransportConnectionFactory.makeConnection() }
        )
    }

    /// Creates an Icecast relay with a custom transport factory (for testing).
    ///
    /// - Parameters:
    ///   - configuration: The relay configuration.
    ///   - transportFactory: Factory for creating transport connections.
    init(
        configuration: IcecastRelayConfiguration,
        transportFactory: @Sendable @escaping () -> any TransportConnection
    ) {
        self.configuration = configuration
        self.transportFactory = transportFactory

        var audioCont: AsyncStream<AudioChunk>.Continuation?
        self.audioStreamStorage = AsyncStream { audioCont = $0 }
        self.audioContinuation = audioCont

        var eventCont: AsyncStream<RelayEvent>.Continuation?
        self.eventStreamStorage = AsyncStream { eventCont = $0 }
        self.eventContinuation = eventCont
    }

    // MARK: - Connection

    /// Connects to the source stream and starts receiving audio.
    ///
    /// - Throws: ``IcecastError/relayConnectionFailed(url:reason:)`` on failure.
    public func connect() async throws {
        guard !connected else { return }

        let client = ListenerHTTPClient(
            configuration: configuration,
            transportFactory: transportFactory
        )
        httpClient = client

        let headers = try await client.connect()
        connected = true
        totalBytesReceived = 0

        let detectedType = resolveContentType(headers.contentType)
        contentType = detectedType
        server = headers.serverVersion

        eventContinuation?.yield(
            .connected(
                serverVersion: headers.serverVersion,
                contentType: detectedType
            )
        )

        startReadLoop(
            client: client,
            metaint: headers.icyMetaint,
            detectedContentType: detectedType ?? .mp3
        )
    }

    /// Disconnects from the source stream.
    public func disconnect() async {
        readTask?.cancel()
        readTask = nil

        if let client = httpClient {
            await client.disconnect()
        }
        httpClient = nil

        if connected {
            connected = false
            eventContinuation?.yield(.disconnected(error: nil))
        }

        audioContinuation?.finish()
        audioContinuation = nil
    }

    // MARK: - Audio Stream

    /// Async stream of audio chunks received from the source.
    ///
    /// Terminates when disconnected or the stream ends (and no reconnect policy
    /// is configured).
    public nonisolated var audioStream: AsyncStream<AudioChunk> {
        audioStreamStorage
    }

    // MARK: - State & Monitoring

    /// Whether the relay is currently connected.
    public var isConnected: Bool { connected }

    /// Stream metadata detected from ICY inline updates.
    public var currentMetadata: ICYMetadata? { metadata }

    /// Content type detected from HTTP response headers.
    public var detectedContentType: AudioContentType? { contentType }

    /// Total bytes received since the last ``connect()`` call.
    public var bytesReceived: Int64 { totalBytesReceived }

    /// Server version from response headers (e.g. `"Icecast 2.4.4"`).
    public var serverVersion: String? { server }

    /// Events stream for relay lifecycle events.
    public nonisolated var events: AsyncStream<RelayEvent> {
        eventStreamStorage
    }

    // MARK: - Private

    /// Starts the read loop that pulls data from the HTTP client.
    private func startReadLoop(
        client: ListenerHTTPClient,
        metaint: Int?,
        detectedContentType: AudioContentType
    ) {
        readTask = Task { [weak self] in
            guard let self else { return }
            var demuxer = ICYStreamDemuxer(metaint: metaint)

            while !Task.isCancelled {
                let chunk: Data?
                do {
                    chunk = try await client.readChunk(
                        size: self.configuration.bufferSize
                    )
                } catch {
                    break
                }

                guard let data = chunk else {
                    await self.handleStreamEnd()
                    return
                }

                let result = demuxer.feed(data)

                if !result.audioBytes.isEmpty {
                    let offset = await self.addBytesReceived(
                        Int64(result.audioBytes.count)
                    )
                    let audioChunk = AudioChunk(
                        data: result.audioBytes,
                        metadata: result.metadata,
                        contentType: detectedContentType,
                        byteOffset: offset
                    )
                    await self.audioContinuation?.yield(audioChunk)
                }

                if let newMetadata = result.metadata {
                    await self.updateMetadata(newMetadata)
                }
            }
        }
    }

    /// Updates byte counter and returns the new total.
    private func addBytesReceived(_ count: Int64) -> Int64 {
        totalBytesReceived += count
        return totalBytesReceived
    }

    /// Updates the current metadata and emits an event.
    private func updateMetadata(_ newMetadata: ICYMetadata) {
        metadata = newMetadata
        eventContinuation?.yield(.metadataUpdated(newMetadata))
    }

    /// Handles a clean stream end — reconnects if policy is configured.
    private func handleStreamEnd() async {
        eventContinuation?.yield(.streamEnded)

        guard let policy = configuration.reconnectPolicy,
            policy.isEnabled
        else {
            connected = false
            eventContinuation?.yield(.disconnected(error: nil))
            audioContinuation?.finish()
            audioContinuation = nil
            return
        }

        await attemptReconnection(policy: policy)
    }

    /// Attempts reconnection with exponential backoff.
    private func attemptReconnection(policy: ReconnectPolicy) async {
        if let client = httpClient {
            await client.disconnect()
        }
        httpClient = nil
        connected = false

        for attempt in 1...policy.maxRetries {
            guard !Task.isCancelled else { return }

            eventContinuation?.yield(.reconnecting(attempt: attempt))

            let delay = policy.delay(forAttempt: attempt)
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            let client = ListenerHTTPClient(
                configuration: configuration,
                transportFactory: transportFactory
            )
            httpClient = client

            do {
                let headers = try await client.connect()
                connected = true

                let detectedType = resolveContentType(headers.contentType)
                contentType = detectedType
                server = headers.serverVersion

                eventContinuation?.yield(.reconnected)

                startReadLoop(
                    client: client,
                    metaint: headers.icyMetaint,
                    detectedContentType: detectedType ?? .mp3
                )
                return
            } catch {
                if let client = httpClient {
                    await client.disconnect()
                }
                httpClient = nil
            }
        }

        connected = false
        let error = IcecastError.relayConnectionFailed(
            url: configuration.sourceURL,
            reason: "Max reconnection attempts exceeded"
        )
        eventContinuation?.yield(.disconnected(error: error))
        audioContinuation?.finish()
        audioContinuation = nil
    }

    /// Resolves a content-type string to an ``AudioContentType``.
    private func resolveContentType(_ header: String?) -> AudioContentType? {
        guard let header else { return nil }
        let lower = header.lowercased()
        if lower.contains("audio/mpeg") || lower.contains("audio/mp3") {
            return .mp3
        } else if lower.contains("audio/aac") || lower.contains("audio/aacp") {
            return .aac
        } else if lower.contains("application/ogg") {
            return .oggVorbis
        } else if lower.contains("audio/ogg") {
            return .oggOpus
        }
        return AudioContentType(rawValue: header)
    }
}
