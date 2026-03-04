// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Configuration for local stream recording.
///
/// Controls the output directory, file format, rotation policy,
/// flush interval, and filename pattern for recorded audio files.
public struct RecordingConfiguration: Sendable, Hashable, Codable {

    /// Output directory path.
    public var directory: String

    /// Recording format — raw bytes with matching file extension.
    public var format: RecordingFormat

    /// Maximum file size in bytes before rotation. `nil` = unlimited.
    public var maxFileSize: Int64?

    /// Rotate to a new file every N seconds. `nil` = single file.
    public var splitInterval: TimeInterval?

    /// How often to flush to disk in seconds.
    public var flushInterval: TimeInterval

    /// Filename pattern. Supported tokens: `{date}`, `{mountpoint}`, `{index}`.
    public var filenamePattern: String

    /// Content type — used to determine file extension.
    public var contentType: AudioContentType

    /// Default configuration writing MP3 to the current directory.
    public static let `default` = RecordingConfiguration(
        directory: ".",
        contentType: .mp3
    )

    /// Creates a recording configuration.
    ///
    /// - Parameters:
    ///   - directory: Output directory path.
    ///   - contentType: Audio content type for file extension.
    ///   - format: Recording format. Defaults to `.matchSource`.
    ///   - maxFileSize: Maximum file size in bytes before rotation. Defaults to `nil`.
    ///   - splitInterval: Rotate to a new file every N seconds. Defaults to `nil`.
    ///   - flushInterval: How often to flush to disk in seconds. Defaults to `1.0`.
    ///   - filenamePattern: Filename pattern with tokens. Defaults to `"{date}_{mountpoint}"`.
    public init(
        directory: String,
        contentType: AudioContentType,
        format: RecordingFormat = .matchSource,
        maxFileSize: Int64? = nil,
        splitInterval: TimeInterval? = nil,
        flushInterval: TimeInterval = 1.0,
        filenamePattern: String = "{date}_{mountpoint}"
    ) {
        self.directory = directory
        self.contentType = contentType
        self.format = format
        self.maxFileSize = maxFileSize
        self.splitInterval = splitInterval
        self.flushInterval = flushInterval
        self.filenamePattern = filenamePattern
    }
}

/// Recording format for stream recording.
public enum RecordingFormat: String, Sendable, Hashable, Codable, CaseIterable {

    /// Write raw bytes with the file extension matching the content type
    /// (`.mp3`, `.aac`, `.ogg`, `.opus`).
    case matchSource

    /// Write raw bytes with no extension interpretation (`.raw`).
    case raw
}

// MARK: - AudioContentType File Extension

extension AudioContentType {

    /// File extension for this content type (without leading dot).
    public var fileExtension: String {
        switch self {
        case .mp3: return "mp3"
        case .aac: return "aac"
        case .oggVorbis: return "ogg"
        case .oggOpus: return "opus"
        default: return "raw"
        }
    }
}
