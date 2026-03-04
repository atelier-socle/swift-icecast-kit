// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Snapshot of connection statistics.
public struct ConnectionStatistics: Sendable, Hashable {

    /// Total bytes of audio data sent.
    public var bytesSent: UInt64

    /// Total bytes sent including metadata and protocol overhead.
    public var bytesTotal: UInt64

    /// Total streaming duration in seconds.
    public var duration: TimeInterval

    /// Average bitrate since connection (bits per second).
    public var averageBitrate: Double

    /// Current bitrate estimate (bits per second).
    public var currentBitrate: Double

    /// Number of metadata updates performed.
    public var metadataUpdateCount: Int

    /// Number of successful reconnections.
    public var reconnectionCount: Int

    /// The date when the current connection was established.
    public var connectedSince: Date?

    /// Number of send errors encountered.
    public var sendErrorCount: Int

    /// Average write latency in milliseconds.
    public var averageWriteLatency: Double

    /// Variance of write latency in milliseconds squared.
    public var writeLatencyVariance: Double

    /// Total number of send attempts (successful + failed).
    public var totalSendCount: Int

    /// Creates a connection statistics snapshot with the given values.
    ///
    /// - Parameters:
    ///   - bytesSent: Total audio bytes sent. Defaults to `0`.
    ///   - bytesTotal: Total bytes sent. Defaults to `0`.
    ///   - duration: Streaming duration. Defaults to `0`.
    ///   - averageBitrate: Average bitrate. Defaults to `0`.
    ///   - currentBitrate: Current bitrate. Defaults to `0`.
    ///   - metadataUpdateCount: Metadata update count. Defaults to `0`.
    ///   - reconnectionCount: Reconnection count. Defaults to `0`.
    ///   - connectedSince: Connection start date. Defaults to `nil`.
    ///   - sendErrorCount: Send error count. Defaults to `0`.
    ///   - averageWriteLatency: Average write latency in ms. Defaults to `0`.
    ///   - writeLatencyVariance: Write latency variance in ms². Defaults to `0`.
    ///   - totalSendCount: Total send attempts. Defaults to `0`.
    public init(
        bytesSent: UInt64 = 0,
        bytesTotal: UInt64 = 0,
        duration: TimeInterval = 0,
        averageBitrate: Double = 0,
        currentBitrate: Double = 0,
        metadataUpdateCount: Int = 0,
        reconnectionCount: Int = 0,
        connectedSince: Date? = nil,
        sendErrorCount: Int = 0,
        averageWriteLatency: Double = 0,
        writeLatencyVariance: Double = 0,
        totalSendCount: Int = 0
    ) {
        self.bytesSent = bytesSent
        self.bytesTotal = bytesTotal
        self.duration = duration
        self.averageBitrate = averageBitrate
        self.currentBitrate = currentBitrate
        self.metadataUpdateCount = metadataUpdateCount
        self.reconnectionCount = reconnectionCount
        self.connectedSince = connectedSince
        self.sendErrorCount = sendErrorCount
        self.averageWriteLatency = averageWriteLatency
        self.writeLatencyVariance = writeLatencyVariance
        self.totalSendCount = totalSendCount
    }
}
