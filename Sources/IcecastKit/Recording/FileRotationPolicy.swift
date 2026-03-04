// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Determines when a recording file should be rotated.
///
/// Supports size-based, time-based, or combined rotation strategies.
/// When both limits are set, rotation occurs as soon as either is reached.
public struct FileRotationPolicy: Sendable {

    /// Maximum file size in bytes. `nil` = no size-based rotation.
    public let maxFileSize: Int64?

    /// Maximum recording duration per file. `nil` = no time-based rotation.
    public let splitInterval: TimeInterval?

    /// Creates a rotation policy with the given limits.
    ///
    /// - Parameters:
    ///   - maxFileSize: Maximum file size in bytes.
    ///   - splitInterval: Maximum recording duration per file.
    public init(maxFileSize: Int64? = nil, splitInterval: TimeInterval? = nil) {
        self.maxFileSize = maxFileSize
        self.splitInterval = splitInterval
    }

    /// Returns `true` if rotation should occur given current file size and duration.
    ///
    /// - Parameters:
    ///   - currentSize: Current file size in bytes.
    ///   - currentDuration: Time elapsed since file was opened.
    /// - Returns: Whether the file should be rotated.
    public func shouldRotate(currentSize: Int64, currentDuration: TimeInterval) -> Bool {
        if let max = maxFileSize, currentSize >= max {
            return true
        }
        if let interval = splitInterval, currentDuration >= interval {
            return true
        }
        return false
    }

    /// No rotation — single file for the entire stream.
    public static let none = FileRotationPolicy()

    /// Rotate every hour.
    public static let hourly = FileRotationPolicy(splitInterval: 3600)

    /// Rotate every N seconds.
    ///
    /// - Parameter seconds: The rotation interval in seconds.
    /// - Returns: A rotation policy that rotates at the given interval.
    public static func every(_ seconds: TimeInterval) -> FileRotationPolicy {
        FileRotationPolicy(splitInterval: seconds)
    }

    /// Rotate when file exceeds N bytes.
    ///
    /// - Parameter bytes: The maximum file size in bytes.
    /// - Returns: A rotation policy that rotates at the given size.
    public static func maxSize(_ bytes: Int64) -> FileRotationPolicy {
        FileRotationPolicy(maxFileSize: bytes)
    }
}
