// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Connection state machine for the Icecast client.
///
/// State transitions:
/// ```
/// disconnected → connecting → authenticating → connected → streaming
///       ↑                                          ↓
///       ←←←←←←←← reconnecting ←←←←←←←←←←←←←←←←←←
///       ↑                                          ↓
///       ←←←←←←←← failed ←←←←←←←←←←←←←←←←←←←←←←←←
/// ```
public enum ConnectionState: Sendable, Hashable, CustomStringConvertible {

    /// Not connected to any server.
    case disconnected

    /// TCP connection in progress.
    case connecting

    /// Protocol handshake in progress.
    case authenticating

    /// Connected and ready to send audio data.
    case connected

    /// Actively streaming audio data.
    case streaming

    /// Reconnecting after a connection loss.
    case reconnecting(attempt: Int, nextRetryIn: TimeInterval)

    /// Connection failed with an error.
    case failed(IcecastError)

    /// Whether data can be sent in this state.
    public var canSend: Bool {
        switch self {
        case .connected, .streaming:
            return true
        default:
            return false
        }
    }

    /// Whether the client is in a connected or streaming state.
    public var isActive: Bool {
        switch self {
        case .connected, .streaming:
            return true
        default:
            return false
        }
    }

    public var description: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .authenticating:
            return "authenticating"
        case .connected:
            return "connected"
        case .streaming:
            return "streaming"
        case .reconnecting(let attempt, let nextRetryIn):
            return "reconnecting (attempt \(attempt + 1), next retry in \(String(format: "%.1f", nextRetryIn))s)"
        case .failed(let error):
            return "failed: \(error)"
        }
    }
}
