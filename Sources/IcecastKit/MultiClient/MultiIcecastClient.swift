// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Client for streaming audio to multiple Icecast/SHOUTcast servers simultaneously.
///
/// Wraps multiple ``IcecastClient`` instances and provides a unified API
/// for connecting, streaming, and monitoring across all destinations.
///
/// **Failure isolation**: each destination operates independently —
/// the failure of one never affects the others. Each has its own
/// reconnection loop based on its configured ``ReconnectPolicy``.
///
/// Usage:
/// ```swift
/// let multi = MultiIcecastClient()
/// try await multi.addDestination("primary",
///     configuration: IcecastConfiguration(host: "radio1.example.com", mountpoint: "/live.mp3",
///         credentials: IcecastCredentials(password: "secret1")))
/// try await multi.addDestination("backup",
///     configuration: IcecastConfiguration(host: "radio2.example.com", mountpoint: "/live.mp3",
///         credentials: IcecastCredentials(password: "secret2")))
/// try await multi.connectAll()
/// try await multi.send(audioData)
/// await multi.disconnectAll()
/// ```
public actor MultiIcecastClient {

    // MARK: - Internal Types

    /// Internal entry tracking a single destination.
    private struct DestinationEntry {
        let label: String
        let client: IcecastClient
        let configuration: IcecastConfiguration
        var eventRelayTask: Task<Void, Never>?
    }

    // MARK: - Properties

    private var entries: [String: DestinationEntry] = [:]
    private let eventContinuation: AsyncStream<MultiIcecastEvent>.Continuation
    private let eventStream: AsyncStream<MultiIcecastEvent>
    private let connectionFactory: (@Sendable () -> any TransportConnection)?

    // MARK: - Initialization

    /// Creates a new multi-destination client.
    public init() {
        let (stream, continuation) = AsyncStream<MultiIcecastEvent>.makeStream()
        self.eventStream = stream
        self.eventContinuation = continuation
        self.connectionFactory = nil
    }

    /// Creates a new multi-destination client with a custom connection factory.
    ///
    /// - Parameter connectionFactory: A factory closure for creating transport connections.
    init(connectionFactory: @Sendable @escaping () -> any TransportConnection) {
        let (stream, continuation) = AsyncStream<MultiIcecastEvent>.makeStream()
        self.eventStream = stream
        self.eventContinuation = continuation
        self.connectionFactory = connectionFactory
    }

    deinit {
        for entry in entries.values {
            entry.eventRelayTask?.cancel()
        }
        eventContinuation.finish()
    }

    // MARK: - Destination Management

    /// Adds a destination before connecting.
    ///
    /// - Parameters:
    ///   - label: A unique label for this destination.
    ///   - configuration: The server and stream configuration, including
    ///     ``IcecastConfiguration/credentials`` and ``IcecastConfiguration/reconnectPolicy``.
    /// - Throws: ``IcecastError/destinationAlreadyExists(label:)`` if the label is taken,
    ///   or ``IcecastError/credentialsRequired`` if credentials are not set in the configuration.
    public func addDestination(
        _ label: String,
        configuration: IcecastConfiguration
    ) throws {
        guard entries[label] == nil else {
            throw IcecastError.destinationAlreadyExists(label: label)
        }
        guard let credentials = configuration.credentials else {
            throw IcecastError.credentialsRequired
        }

        let client = makeClient(
            configuration: configuration,
            credentials: credentials
        )
        entries[label] = DestinationEntry(
            label: label,
            client: client,
            configuration: configuration
        )
        eventContinuation.yield(.destinationAdded(label: label))
    }

    /// Removes a destination. No-op if not found.
    ///
    /// - Parameter label: The label of the destination to remove.
    public func removeDestination(label: String) async {
        guard var entry = entries.removeValue(forKey: label) else { return }
        entry.eventRelayTask?.cancel()
        entry.eventRelayTask = nil
        await entry.client.disconnect()
        eventContinuation.yield(.destinationRemoved(label: label))
    }

    /// Adds a destination while already streaming (hot-add).
    ///
    /// Connects the new destination immediately. Subsequent ``send(_:)``
    /// calls will include this destination.
    ///
    /// - Parameters:
    ///   - label: A unique label for this destination.
    ///   - configuration: The server and stream configuration, including
    ///     ``IcecastConfiguration/credentials`` and ``IcecastConfiguration/reconnectPolicy``.
    /// - Throws: ``IcecastError/destinationAlreadyExists(label:)`` if the label is taken,
    ///   ``IcecastError/credentialsRequired`` if credentials are not set,
    ///   or a connection error if the destination fails to connect.
    public func addDestinationLive(
        _ label: String,
        configuration: IcecastConfiguration
    ) async throws {
        guard entries[label] == nil else {
            throw IcecastError.destinationAlreadyExists(label: label)
        }
        guard let credentials = configuration.credentials else {
            throw IcecastError.credentialsRequired
        }

        let client = makeClient(
            configuration: configuration,
            credentials: credentials
        )
        var entry = DestinationEntry(
            label: label,
            client: client,
            configuration: configuration
        )
        entry.eventRelayTask = startEventRelay(label: label, client: client)
        entries[label] = entry

        eventContinuation.yield(.destinationAdded(label: label))
        try await client.connect()
        eventContinuation.yield(.destinationConnected(label: label, serverVersion: nil))
        await checkAllConnected()
    }

    /// Removes a destination while streaming (hot-remove).
    ///
    /// Disconnects cleanly and removes from the rotation.
    /// Subsequent ``send(_:)`` calls will no longer reach this destination.
    ///
    /// - Parameter label: The label of the destination to remove.
    public func removeDestinationLive(label: String) async {
        await removeDestination(label: label)
    }

    // MARK: - Connection

    /// Connects all registered destinations concurrently.
    ///
    /// Uses `withTaskGroup` for parallel connection. Succeeds if at least
    /// one destination connects. Emits ``MultiIcecastEvent/allConnected``
    /// when all destinations are connected.
    ///
    /// - Throws: ``IcecastError/allDestinationsFailed`` if every destination fails.
    ///   No-op if zero destinations are registered.
    public func connectAll() async throws {
        guard !entries.isEmpty else { return }
        ensureEventRelays()

        let results = await connectAllDestinations()
        emitConnectionResults(results)

        let successCount = results.values.filter { $0 }.count
        guard successCount > 0 else {
            throw IcecastError.allDestinationsFailed
        }
        if successCount == entries.count {
            eventContinuation.yield(.allConnected)
        }
    }

    /// Ensures all destinations have event relay tasks running.
    private func ensureEventRelays() {
        for label in entries.keys {
            if entries[label]?.eventRelayTask == nil,
                let client = entries[label]?.client
            {
                entries[label]?.eventRelayTask = startEventRelay(
                    label: label, client: client
                )
            }
        }
    }

    /// Connects all destinations concurrently and returns results.
    private func connectAllDestinations() async -> [String: Bool] {
        let labels = Array(entries.keys)
        var results: [String: Bool] = [:]

        await withTaskGroup(of: (String, Bool).self) { group in
            for label in labels {
                guard let client = entries[label]?.client else { continue }
                group.addTask { [label] in
                    do {
                        try await client.connect()
                        return (label, true)
                    } catch {
                        return (label, false)
                    }
                }
            }
            for await (label, success) in group {
                results[label] = success
            }
        }
        return results
    }

    /// Emits connection/disconnection events based on results.
    private func emitConnectionResults(_ results: [String: Bool]) {
        for (label, success) in results {
            if success {
                eventContinuation.yield(
                    .destinationConnected(label: label, serverVersion: nil)
                )
            } else {
                eventContinuation.yield(
                    .destinationDisconnected(label: label, error: nil)
                )
            }
        }
    }

    /// Disconnects all destinations cleanly.
    ///
    /// Cancels all event relay tasks and disconnects each destination.
    public func disconnectAll() async {
        for label in entries.keys {
            entries[label]?.eventRelayTask?.cancel()
            entries[label]?.eventRelayTask = nil
        }
        await withTaskGroup(of: Void.self) { group in
            for entry in entries.values {
                group.addTask {
                    await entry.client.disconnect()
                }
            }
        }
    }

    // MARK: - Streaming

    /// Sends audio data to all connected destinations concurrently.
    ///
    /// Never throws on partial failure — emits
    /// ``MultiIcecastEvent/sendComplete(successCount:failureCount:)``
    /// with the results. Only throws if no destinations are available.
    ///
    /// - Parameter data: The audio data to send.
    /// - Throws: ``IcecastError/notConnected`` if no destinations are registered.
    public func send(_ data: Data) async throws {
        guard !entries.isEmpty else {
            throw IcecastError.notConnected
        }

        let activeEntries = entries.values.filter { entry in
            let label = entry.label
            return entries[label] != nil
        }

        var successCount = 0
        var failureCount = 0

        await withTaskGroup(of: Bool.self) { group in
            for entry in activeEntries {
                group.addTask {
                    do {
                        try await entry.client.send(data)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            for await success in group {
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
        }

        eventContinuation.yield(
            .sendComplete(
                successCount: successCount,
                failureCount: failureCount
            )
        )
    }

    /// Sends audio data from a raw buffer pointer to all connected destinations.
    ///
    /// Converts the buffer to `Data` and forwards to ``send(_:)``.
    ///
    /// - Parameters:
    ///   - bytes: The raw buffer pointer containing audio data.
    ///   - count: The number of bytes to send.
    /// - Throws: ``IcecastError/notConnected`` if no destinations are registered.
    public func send(bytes: UnsafeRawBufferPointer, count: Int) async throws {
        let effectiveCount = min(count, bytes.count)
        guard effectiveCount > 0, let baseAddress = bytes.baseAddress else {
            return
        }
        let data = Data(bytes: baseAddress, count: effectiveCount)
        try await send(data)
    }

    /// Updates ICY metadata on all connected destinations.
    ///
    /// Silently ignores destinations that are not connected.
    /// Emits ``MultiIcecastEvent/metadataUpdated(label:)`` for each
    /// destination that succeeds.
    ///
    /// - Parameter metadata: The metadata to update.
    public func updateMetadata(_ metadata: ICYMetadata) async {
        await withTaskGroup(of: String?.self) { group in
            for entry in entries.values {
                let label = entry.label
                group.addTask {
                    let isConnected = await entry.client.isConnected
                    guard isConnected else { return nil }
                    do {
                        try await entry.client.updateMetadata(metadata)
                        return label
                    } catch {
                        return nil
                    }
                }
            }
            for await label in group {
                if let label {
                    eventContinuation.yield(.metadataUpdated(label: label))
                }
            }
        }
    }

    // MARK: - Monitoring

    /// Current snapshot of all destinations.
    public var destinations: [IcecastDestination] {
        get async {
            var result: [IcecastDestination] = []
            for entry in entries.values {
                let state = await entry.client.state
                let stats = await entry.client.statistics
                result.append(
                    IcecastDestination(
                        label: entry.label,
                        configuration: entry.configuration,
                        state: state,
                        statistics: stats
                    )
                )
            }
            return result
        }
    }

    /// Unified event stream — events from all destinations, tagged by label.
    public nonisolated var events: AsyncStream<MultiIcecastEvent> {
        eventStream
    }

    /// Quality snapshot per destination label.
    ///
    /// Only includes destinations that are currently connected.
    /// Returns an empty dictionary if no destinations are connected.
    public var connectionQualities: [String: ConnectionQuality] {
        get async {
            var result: [String: ConnectionQuality] = [:]
            for entry in entries.values {
                if let quality = await entry.client.connectionQuality {
                    result[entry.label] = quality
                }
            }
            return result
        }
    }

    /// Aggregated quality across all connected destinations.
    ///
    /// Averages per-metric scores across all connected destinations,
    /// then computes a weighted composite score. Returns `nil` if
    /// no destinations are connected.
    public var aggregatedQuality: ConnectionQuality? {
        get async {
            let qualities = await connectionQualities
            guard !qualities.isEmpty else { return nil }
            let count = Double(qualities.count)

            let avgWl =
                qualities.values.map(\.writeLatencyScore).reduce(0, +) / count
            let avgSt =
                qualities.values.map(\.stabilityScore).reduce(0, +) / count
            let avgTp =
                qualities.values.map(\.throughputScore).reduce(0, +) / count
            let avgSs =
                qualities.values.map(\.sendSuccessScore).reduce(0, +) / count
            let avgRc =
                qualities.values.map(\.reconnectionScore).reduce(0, +) / count

            let score =
                avgWl * 0.30
                + avgSt * 0.25
                + avgTp * 0.20
                + avgSs * 0.15
                + avgRc * 0.10
            let grade = QualityGrade(score: score)

            let partial = ConnectionQuality(
                score: score, grade: grade,
                writeLatencyScore: avgWl, stabilityScore: avgSt,
                throughputScore: avgTp, sendSuccessScore: avgSs,
                reconnectionScore: avgRc, recommendation: nil
            )
            let engine = QualityRecommendationEngine()
            let recommendation = engine.recommendation(for: partial)

            return ConnectionQuality(
                score: score, grade: grade,
                writeLatencyScore: avgWl, stabilityScore: avgSt,
                throughputScore: avgTp, sendSuccessScore: avgSs,
                reconnectionScore: avgRc, recommendation: recommendation
            )
        }
    }

    /// Statistics snapshot aggregating all destinations.
    public var statistics: MultiIcecastStatistics {
        get async {
            var perDest: [String: ConnectionStatistics] = [:]
            var connectedCount = 0
            var reconnectingCount = 0

            for entry in entries.values {
                let stats = await entry.client.statistics
                perDest[entry.label] = stats

                let state = await entry.client.state
                if state.isActive {
                    connectedCount += 1
                }
                if case .reconnecting = state {
                    reconnectingCount += 1
                }
            }

            let aggregated = MultiIcecastStatistics.aggregate(
                Array(perDest.values)
            )

            return MultiIcecastStatistics(
                perDestination: perDest,
                aggregated: aggregated,
                connectedCount: connectedCount,
                reconnectingCount: reconnectingCount,
                totalCount: entries.count
            )
        }
    }

    // MARK: - Private Helpers

    /// Creates an IcecastClient with the appropriate factory.
    private func makeClient(
        configuration: IcecastConfiguration,
        credentials: IcecastCredentials
    ) -> IcecastClient {
        if let factory = connectionFactory {
            return IcecastClient(
                configuration: configuration,
                credentials: credentials,
                reconnectPolicy: configuration.reconnectPolicy,
                connectionFactory: factory
            )
        }
        return IcecastClient(
            configuration: configuration,
            credentials: credentials,
            reconnectPolicy: configuration.reconnectPolicy
        )
    }

    /// Starts an event relay task that maps IcecastClient events to MultiIcecastEvents.
    private func startEventRelay(
        label: String,
        client: IcecastClient
    ) -> Task<Void, Never> {
        let continuation = eventContinuation
        return Task { [label] in
            for await event in client.events {
                guard !Task.isCancelled else { return }
                switch event {
                case .connected:
                    continuation.yield(
                        .destinationConnected(label: label, serverVersion: nil)
                    )
                case .disconnected(let reason):
                    let error: IcecastError? =
                        if case .networkError(let msg) = reason {
                            .connectionLost(reason: msg)
                        } else {
                            nil
                        }
                    continuation.yield(
                        .destinationDisconnected(label: label, error: error)
                    )
                case .reconnecting(let attempt, _):
                    continuation.yield(
                        .destinationReconnecting(label: label, attempt: attempt)
                    )
                case .metadataUpdated:
                    continuation.yield(.metadataUpdated(label: label))
                case .error, .statistics, .protocolNegotiated,
                    .bitrateRecommendation, .qualityChanged,
                    .qualityWarning, .recordingStarted,
                    .recordingStopped, .recordingFileRotated,
                    .recordingError:
                    break
                }
            }
        }
    }

    /// Checks if all destinations are connected and emits `.allConnected`.
    private func checkAllConnected() async {
        guard !entries.isEmpty else { return }
        for entry in entries.values {
            let connected = await entry.client.isConnected
            if !connected { return }
        }
        eventContinuation.yield(.allConnected)
    }

    // MARK: - Metrics Export

    /// Attaches a metrics exporter for all destinations.
    ///
    /// Each destination receives labels including its label, mountpoint, and server.
    /// Pass `nil` as exporter to detach the current exporter from all destinations.
    ///
    /// - Parameters:
    ///   - exporter: The metrics exporter to attach, or `nil` to detach.
    ///   - interval: Export interval in seconds. Clamped to minimum 1.0.
    public func setMetricsExporter<Exporter: IcecastMetricsExporter>(
        _ exporter: Exporter?,
        interval: TimeInterval = 10.0
    ) async {
        for entry in entries.values {
            let labels: [String: String] = [
                "destination": entry.label
            ]
            await entry.client.setMetricsExporter(
                exporter, interval: interval, labels: labels
            )
        }
    }
}
