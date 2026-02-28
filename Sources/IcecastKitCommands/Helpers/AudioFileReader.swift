// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import IcecastKit

/// Errors that can occur when reading audio files.
public enum AudioFileError: Error, Sendable {

    /// The file was not found at the specified path.
    case fileNotFound(String)

    /// The file could not be read.
    case readError(String)

    /// The audio content type could not be detected.
    case unknownContentType(String)
}

/// Reads audio files in chunks for streaming to a server.
///
/// Supports MP3, AAC, OGG/Vorbis, and OGG/Opus formats.
/// Detects content type from file extension and reads data
/// in configurable chunk sizes suitable for live-pace streaming.
public struct AudioFileReader: Sendable {

    /// The detected audio content type.
    public let contentType: AudioContentType

    /// The file size in bytes.
    public let fileSize: UInt64

    /// The file path.
    public let filePath: String

    private let fileData: Data
    private var offset: Int

    /// Open an audio file for reading.
    ///
    /// - Parameters:
    ///   - path: Path to the audio file.
    ///   - contentType: Override content type (nil = auto-detect from extension).
    /// - Throws: ``AudioFileError`` if file doesn't exist, can't be read,
    ///   or type can't be detected.
    public init(path: String, contentType: AudioContentType? = nil) throws {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw AudioFileError.fileNotFound(path)
        }

        let resolvedType: AudioContentType
        if let contentType {
            resolvedType = contentType
        } else if let detected = Self.detectContentType(from: path) {
            resolvedType = detected
        } else {
            throw AudioFileError.unknownContentType(path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AudioFileError.readError("\(error)")
        }

        self.filePath = path
        self.contentType = resolvedType
        self.fileData = data
        self.fileSize = UInt64(data.count)
        self.offset = 0
    }

    /// Read the next chunk of audio data.
    ///
    /// - Parameter size: Chunk size in bytes (default: 4096).
    /// - Returns: Data chunk, or nil if end of file reached.
    public mutating func readChunk(size: Int = 4096) throws -> Data? {
        guard offset < fileData.count else { return nil }
        let end = min(offset + size, fileData.count)
        let chunk = fileData[offset..<end]
        offset = end
        return Data(chunk)
    }

    /// Reset to the beginning of the file (for looping).
    public mutating func reset() throws {
        offset = 0
    }

    /// Whether end of file has been reached.
    public var isEOF: Bool {
        offset >= fileData.count
    }

    /// Estimated bitrate from file size and common durations.
    ///
    /// Returns nil if bitrate cannot be determined.
    public var estimatedBitrate: Int? {
        guard fileSize > 0 else { return nil }
        // Common MP3 bitrates: estimate based on file size
        // Assume ~3.5 minutes average song at 128kbps = ~3.36 MB
        // This is a rough heuristic; return nil for files too small to estimate
        let sizeKB = Double(fileSize) / 1024.0
        if sizeKB < 10 { return nil }
        // Rough estimate: assume 128 kbps as default for files that look like songs
        return 128_000
    }

    /// Detect content type from file extension.
    ///
    /// - Parameter path: The file path.
    /// - Returns: The detected content type, or nil if unknown.
    public static func detectContentType(from path: String) -> AudioContentType? {
        AudioContentType.detect(from: path)
    }
}
