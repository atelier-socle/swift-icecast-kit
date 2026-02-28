// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Terminal progress display for streaming operations.
///
/// Displays streaming progress with elapsed time, bytes sent,
/// bitrate, and metadata information. Uses carriage return for
/// in-place updates on a single line.
public struct ProgressDisplay: Sendable {

    /// The color output instance for formatting.
    public let color: ColorOutput

    /// Create a progress display.
    ///
    /// - Parameter color: The color output configuration.
    public init(color: ColorOutput = ColorOutput()) {
        self.color = color
    }

    /// Format a status line for streaming progress.
    ///
    /// Example: `"⏺ Streaming  00:05:32  │  2.4 MB sent  │  128.0 kbps  │  Artist - Song"`
    ///
    /// - Parameters:
    ///   - elapsed: Elapsed streaming time in seconds.
    ///   - bytesSent: Total bytes sent.
    ///   - bitrate: Current bitrate in bits per second.
    ///   - title: Current stream title, if any.
    /// - Returns: A formatted status line.
    public func formatStreamingStatus(
        elapsed: TimeInterval,
        bytesSent: UInt64,
        bitrate: Double,
        title: String?
    ) -> String {
        var parts = [
            color.success("⏺ Streaming"),
            Self.formatDuration(elapsed),
            "\(Self.formatBytes(bytesSent)) sent",
            Self.formatBitrate(bitrate)
        ]
        if let title, !title.isEmpty {
            parts.append(title)
        }
        return parts.joined(separator: "  │  ")
    }

    /// Format connection status.
    ///
    /// Example: `"✓ Connected to radio.example.com:8000/live.mp3 (Icecast PUT)"`
    ///
    /// - Parameters:
    ///   - host: The server hostname.
    ///   - port: The server port.
    ///   - mountpoint: The mountpoint path.
    ///   - protocolName: The negotiated protocol name.
    /// - Returns: A formatted connection status line.
    public func formatConnected(
        host: String,
        port: Int,
        mountpoint: String,
        protocolName: String
    ) -> String {
        color.success("✓ Connected to \(host):\(port)\(mountpoint) (\(protocolName))")
    }

    /// Format disconnection status.
    ///
    /// - Parameter reason: The disconnection reason.
    /// - Returns: A formatted disconnection status line.
    public func formatDisconnected(reason: String) -> String {
        color.warning("✗ Disconnected: \(reason)")
    }

    /// Format reconnection attempt.
    ///
    /// Example: `"⟳ Reconnecting (attempt 3/10, next retry in 4.0s)..."`
    ///
    /// - Parameters:
    ///   - attempt: The current attempt number (0-based).
    ///   - maxRetries: The maximum number of retries.
    ///   - delay: The delay before the next retry.
    /// - Returns: A formatted reconnection status line.
    public func formatReconnecting(
        attempt: Int,
        maxRetries: Int,
        delay: TimeInterval
    ) -> String {
        let delayStr = String(format: "%.1f", delay)
        return color.warning(
            "⟳ Reconnecting (attempt \(attempt + 1)/\(maxRetries), next retry in \(delayStr)s)..."
        )
    }

    /// Format error message.
    ///
    /// - Parameter message: The error message.
    /// - Returns: A formatted error line.
    public func formatError(_ message: String) -> String {
        color.error("✗ Error: \(message)")
    }

    /// Format bytes into human-readable string (B, KB, MB, GB).
    ///
    /// Uses 1024-based units.
    ///
    /// - Parameter bytes: The byte count.
    /// - Returns: A formatted string like `"2.4 MB"`.
    public static func formatBytes(_ bytes: UInt64) -> String {
        let bytesDouble = Double(bytes)
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", bytesDouble / 1024.0)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", bytesDouble / (1024.0 * 1024.0))
        } else {
            return String(format: "%.1f GB", bytesDouble / (1024.0 * 1024.0 * 1024.0))
        }
    }

    /// Format duration into HH:MM:SS.
    ///
    /// - Parameter seconds: The duration in seconds.
    /// - Returns: A formatted string like `"01:30:00"`.
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    /// Format bitrate into human-readable string (kbps).
    ///
    /// - Parameter bitsPerSecond: The bitrate in bits per second.
    /// - Returns: A formatted string like `"128.0 kbps"`.
    public static func formatBitrate(_ bitsPerSecond: Double) -> String {
        String(format: "%.1f kbps", bitsPerSecond / 1000.0)
    }
}
