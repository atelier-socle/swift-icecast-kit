// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Statistics snapshot for a stream recording session.
public struct RecordingStatistics: Sendable {

    /// Total recorded duration in seconds.
    public let duration: TimeInterval

    /// Total bytes written across all files.
    public let bytesWritten: Int64

    /// Number of files created (1 if no rotation).
    public let filesCreated: Int

    /// Path of the current (or last) recording file.
    public let currentFilePath: String?

    /// Whether recording is currently active.
    public let isRecording: Bool
}
