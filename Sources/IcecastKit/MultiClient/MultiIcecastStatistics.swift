// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Aggregated statistics across all destinations in a multi-destination setup.
///
/// Provides both per-destination breakdowns and a combined aggregate view.
public struct MultiIcecastStatistics: Sendable {

    /// Per-destination statistics keyed by label.
    public let perDestination: [String: ConnectionStatistics]

    /// Aggregated statistics across all active destinations.
    public let aggregated: ConnectionStatistics

    /// Number of currently connected destinations.
    public let connectedCount: Int

    /// Number of destinations currently reconnecting.
    public let reconnectingCount: Int

    /// Total destinations registered.
    public let totalCount: Int

    /// Creates a multi-destination statistics snapshot.
    ///
    /// - Parameters:
    ///   - perDestination: Per-destination statistics keyed by label.
    ///   - aggregated: Aggregated statistics across all destinations.
    ///   - connectedCount: Number of connected destinations.
    ///   - reconnectingCount: Number of reconnecting destinations.
    ///   - totalCount: Total registered destinations.
    public init(
        perDestination: [String: ConnectionStatistics],
        aggregated: ConnectionStatistics,
        connectedCount: Int,
        reconnectingCount: Int,
        totalCount: Int
    ) {
        self.perDestination = perDestination
        self.aggregated = aggregated
        self.connectedCount = connectedCount
        self.reconnectingCount = reconnectingCount
        self.totalCount = totalCount
    }

    /// Aggregates per-destination statistics into a combined snapshot.
    ///
    /// - Parameter stats: Per-destination statistics values.
    /// - Returns: A combined ``ConnectionStatistics`` with summed counters.
    static func aggregate(_ stats: [ConnectionStatistics]) -> ConnectionStatistics {
        var result = ConnectionStatistics()
        for s in stats {
            result.bytesSent += s.bytesSent
            result.bytesTotal += s.bytesTotal
            result.metadataUpdateCount += s.metadataUpdateCount
            result.reconnectionCount += s.reconnectionCount
            result.sendErrorCount += s.sendErrorCount
        }

        let durations = stats.compactMap { $0.connectedSince }.map { Date().timeIntervalSince($0) }
        if let maxDuration = durations.max() {
            result.duration = maxDuration
        }

        if result.duration > 0 {
            result.averageBitrate = Double(result.bytesTotal) * 8.0 / result.duration
        }

        let bitrates = stats.map(\.currentBitrate).filter { $0 > 0 }
        if !bitrates.isEmpty {
            result.currentBitrate = bitrates.reduce(0, +) / Double(bitrates.count)
        }

        result.connectedSince = stats.compactMap(\.connectedSince).min()
        return result
    }
}
