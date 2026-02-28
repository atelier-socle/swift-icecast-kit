// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Monitors connection health, aggregates statistics, and emits events.
///
/// The monitor acts as the central event bus for the Icecast client.
/// It tracks bytes sent, computes bitrate, measures connection duration,
/// and periodically emits statistics snapshots via the event stream.
///
/// All events emitted by the client flow through the monitor, making
/// the ``events`` AsyncStream the single source of truth for consumers.
public actor ConnectionMonitor {

    // MARK: - Properties

    private let eventContinuation: AsyncStream<ConnectionEvent>.Continuation
    private var bytesSent: UInt64 = 0
    private var bytesTotal: UInt64 = 0
    private var metadataUpdateCount: Int = 0
    private var reconnectionCount: Int = 0
    private var sendErrorCount: Int = 0
    private var connectedSince: Date?
    private let statisticsInterval: TimeInterval?
    private var periodicTask: Task<Void, Never>?
    private var rollingWindow: [(timestamp: Date, bytes: Int)] = []
    private let windowDuration: TimeInterval = 5.0

    /// Stream of all connection events.
    ///
    /// Consumers can iterate over this stream to receive real-time
    /// notifications of connection state changes, errors, metadata
    /// updates, and periodic statistics.
    public nonisolated let events: AsyncStream<ConnectionEvent>

    /// Current statistics snapshot.
    public var statistics: ConnectionStatistics {
        var stats = ConnectionStatistics(
            bytesSent: bytesSent,
            bytesTotal: bytesTotal,
            metadataUpdateCount: metadataUpdateCount,
            reconnectionCount: reconnectionCount,
            connectedSince: connectedSince,
            sendErrorCount: sendErrorCount
        )

        if let since = connectedSince {
            stats.duration = Date().timeIntervalSince(since)
            if stats.duration > 0 {
                stats.averageBitrate = Double(bytesTotal) * 8.0 / stats.duration
            }
        }

        stats.currentBitrate = computeCurrentBitrate()
        return stats
    }

    // MARK: - Initialization

    /// Create a connection monitor.
    ///
    /// - Parameter statisticsInterval: Interval in seconds between automatic
    ///   statistics event emissions. Pass `nil` to disable periodic stats.
    ///   Default is 5.0 seconds.
    public init(statisticsInterval: TimeInterval? = 5.0) {
        self.statisticsInterval = statisticsInterval
        let (stream, continuation) = AsyncStream<ConnectionEvent>.makeStream()
        self.events = stream
        self.eventContinuation = continuation
    }

    deinit {
        periodicTask?.cancel()
        eventContinuation.finish()
    }

    // MARK: - Recording

    /// Record bytes sent through the connection.
    ///
    /// Updates ``bytesSent``, ``bytesTotal``, recalculates ``currentBitrate``
    /// and ``averageBitrate``.
    ///
    /// - Parameter count: The number of bytes sent.
    public func recordBytesSent(_ count: Int) {
        guard count > 0 else { return }
        let amount = UInt64(count)
        bytesSent += amount
        bytesTotal += amount

        let now = Date()
        rollingWindow.append((timestamp: now, bytes: count))
        pruneRollingWindow(now: now)
    }

    /// Record a metadata update.
    ///
    /// Increments ``metadataUpdateCount`` in statistics.
    public func recordMetadataUpdate() {
        metadataUpdateCount += 1
    }

    /// Record a reconnection attempt.
    ///
    /// Increments ``reconnectionCount`` in statistics.
    public func recordReconnection() {
        reconnectionCount += 1
    }

    /// Record a send error.
    ///
    /// Increments ``sendErrorCount`` in statistics.
    public func recordSendError() {
        sendErrorCount += 1
    }

    // MARK: - Connection Lifecycle

    /// Mark the connection as established.
    ///
    /// Sets ``connectedSince`` to the current date and starts
    /// the periodic statistics emission timer (if configured).
    public func markConnected() {
        connectedSince = Date()
        startPeriodicEmission()
    }

    /// Mark the connection as disconnected.
    ///
    /// Clears ``connectedSince`` and stops the periodic statistics timer.
    public func markDisconnected() {
        connectedSince = nil
        stopPeriodicEmission()
    }

    // MARK: - Event Emission

    /// Emit a connection event to all subscribers.
    ///
    /// - Parameter event: The event to emit.
    public func emit(_ event: ConnectionEvent) {
        eventContinuation.yield(event)
    }

    // MARK: - Reset

    /// Reset all statistics and stop periodic emission.
    public func reset() {
        bytesSent = 0
        bytesTotal = 0
        metadataUpdateCount = 0
        reconnectionCount = 0
        sendErrorCount = 0
        connectedSince = nil
        rollingWindow.removeAll()
        stopPeriodicEmission()
    }

    // MARK: - Private Helpers

    /// Computes the current bitrate from the rolling window.
    private func computeCurrentBitrate() -> Double {
        guard rollingWindow.count >= 2 else { return 0 }
        guard let first = rollingWindow.first, let last = rollingWindow.last else {
            return 0
        }
        let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
        guard elapsed > 0 else { return 0 }
        let totalBytes = rollingWindow.reduce(0) { $0 + $1.bytes }
        return Double(totalBytes) * 8.0 / elapsed
    }

    /// Prunes entries older than the rolling window duration.
    private func pruneRollingWindow(now: Date) {
        let cutoff = now.addingTimeInterval(-windowDuration)
        rollingWindow.removeAll { $0.timestamp < cutoff }
    }

    /// Starts periodic statistics emission if configured.
    private func startPeriodicEmission() {
        guard let interval = statisticsInterval else { return }
        stopPeriodicEmission()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let stats = await self.statistics
                await self.emit(.statistics(stats))
            }
        }
    }

    /// Stops periodic statistics emission.
    private func stopPeriodicEmission() {
        periodicTask?.cancel()
        periodicTask = nil
    }
}
