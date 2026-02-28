// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Represents an audio content type (MIME type) for streaming.
///
/// Common audio formats supported by Icecast and SHOUTcast servers.
public struct AudioContentType: RawRepresentable, Sendable, Hashable, Codable {

    /// The MIME type string.
    public var rawValue: String

    /// Creates an audio content type from a raw MIME type string.
    ///
    /// - Parameter rawValue: The MIME type string (e.g., `"audio/mpeg"`).
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// MPEG Layer 3 audio (`audio/mpeg`).
    public static let mp3 = AudioContentType(rawValue: "audio/mpeg")

    /// Advanced Audio Coding (`audio/aac`).
    public static let aac = AudioContentType(rawValue: "audio/aac")

    /// Ogg Vorbis audio (`application/ogg`).
    public static let oggVorbis = AudioContentType(rawValue: "application/ogg")

    /// Ogg Opus audio (`audio/ogg`).
    public static let oggOpus = AudioContentType(rawValue: "audio/ogg")

    /// All known audio content types.
    public static var allCases: [AudioContentType] {
        [.mp3, .aac, .oggVorbis, .oggOpus]
    }

    /// Detects the audio content type from a filename extension.
    ///
    /// - Parameter filename: The filename or path to inspect.
    /// - Returns: The detected content type, or `nil` if the extension is unknown.
    public static func detect(from filename: String) -> AudioContentType? {
        let lowered = filename.lowercased()
        if lowered.hasSuffix(".mp3") {
            return .mp3
        } else if lowered.hasSuffix(".aac") || lowered.hasSuffix(".m4a") {
            return .aac
        } else if lowered.hasSuffix(".ogg") || lowered.hasSuffix(".oga") {
            return .oggVorbis
        } else if lowered.hasSuffix(".opus") {
            return .oggOpus
        }
        return nil
    }
}

/// Information about a radio station for Icecast/SHOUTcast headers.
///
/// These values are sent as `ice-*` (Icecast) or `icy-*` (SHOUTcast)
/// headers during the initial handshake.
public struct StationInfo: Sendable, Hashable, Codable {

    /// The station name.
    public var name: String?

    /// A description of the station.
    public var description: String?

    /// The station's website URL.
    public var url: String?

    /// The station's genre(s), semicolon-separated.
    public var genre: String?

    /// Whether the station should be listed in public directories.
    public var isPublic: Bool

    /// The audio bitrate in kbps.
    public var bitrate: Int?

    /// The audio sample rate in Hz.
    public var sampleRate: Int?

    /// The number of audio channels.
    public var channels: Int?

    /// Creates station information with the given parameters.
    ///
    /// - Parameters:
    ///   - name: The station name.
    ///   - description: A description of the station.
    ///   - url: The station's website URL.
    ///   - genre: The station's genre(s).
    ///   - isPublic: Whether to list in public directories. Defaults to `false`.
    ///   - bitrate: The audio bitrate in kbps.
    ///   - sampleRate: The audio sample rate in Hz.
    ///   - channels: The number of audio channels.
    public init(
        name: String? = nil,
        description: String? = nil,
        url: String? = nil,
        genre: String? = nil,
        isPublic: Bool = false,
        bitrate: Int? = nil,
        sampleRate: Int? = nil,
        channels: Int? = nil
    ) {
        self.name = name
        self.description = description
        self.url = url
        self.genre = genre
        self.isPublic = isPublic
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
    }

    /// Builds the `ice-audio-info` header value from available audio parameters.
    ///
    /// Format: `ice-channels=2;ice-samplerate=44100;ice-bitrate=128`
    ///
    /// - Returns: The formatted header value, or `nil` if no audio info is available.
    public func audioInfoHeaderValue() -> String? {
        var parts: [String] = []
        if let channels {
            parts.append("ice-channels=\(channels)")
        }
        if let sampleRate {
            parts.append("ice-samplerate=\(sampleRate)")
        }
        if let bitrate {
            parts.append("ice-bitrate=\(bitrate)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ";")
    }
}
