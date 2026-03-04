// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Events emitted by the Icecast client during its lifecycle.
public enum ConnectionEvent: Sendable {

    /// Successfully connected to the server.
    case connected(host: String, port: Int, mountpoint: String, protocolName: String)

    /// Disconnected from the server.
    case disconnected(reason: DisconnectReason)

    /// Attempting to reconnect.
    case reconnecting(attempt: Int, delay: TimeInterval)

    /// Metadata was updated (via admin API or inline).
    case metadataUpdated(ICYMetadata, method: MetadataUpdateMethod)

    /// An error occurred.
    case error(IcecastError)

    /// Periodic statistics snapshot.
    case statistics(ConnectionStatistics)

    /// Protocol was successfully negotiated.
    case protocolNegotiated(ProtocolMode)

    /// Adaptive bitrate recommendation based on network conditions.
    case bitrateRecommendation(BitrateRecommendation)

    /// Connection quality snapshot updated.
    case qualityChanged(ConnectionQuality)

    /// Quality warning when grade transitions to `.poor` or `.critical`.
    case qualityWarning(String)

    /// Recording started at the given file path.
    case recordingStarted(path: String)

    /// Recording stopped with final statistics.
    case recordingStopped(statistics: RecordingStatistics)

    /// Recording file rotated to a new path.
    case recordingFileRotated(newPath: String)

    /// An error occurred during recording.
    case recordingError(IcecastError)
}

/// The method used to update metadata.
public enum MetadataUpdateMethod: Sendable, Hashable {

    /// Metadata updated via Icecast admin HTTP API.
    case adminAPI

    /// Metadata sent inline in the audio stream.
    case inline
}

/// Reason for disconnection.
public enum DisconnectReason: Sendable, Hashable, CustomStringConvertible {

    /// Client explicitly requested disconnection.
    case requested

    /// Server closed the connection.
    case serverClosed

    /// A network error occurred.
    case networkError(String)

    /// Authentication was rejected by the server.
    case authenticationFailed

    /// The mountpoint is already in use.
    case mountpointInUse

    /// Maximum reconnection retries were exceeded.
    case maxRetriesExceeded

    /// The server rejected the content type.
    case contentTypeRejected

    public var description: String {
        switch self {
        case .requested:
            return "disconnected by request"
        case .serverClosed:
            return "server closed connection"
        case .networkError(let reason):
            return "network error: \(reason)"
        case .authenticationFailed:
            return "authentication failed"
        case .mountpointInUse:
            return "mountpoint in use"
        case .maxRetriesExceeded:
            return "max reconnection retries exceeded"
        case .contentTypeRejected:
            return "content type rejected"
        }
    }
}
