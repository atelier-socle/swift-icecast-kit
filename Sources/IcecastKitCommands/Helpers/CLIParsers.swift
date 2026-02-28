// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import IcecastKit

/// Errors that can occur when parsing CLI arguments.
public enum CLIParseError: Error, Sendable {

    /// The protocol mode string is invalid.
    case invalidProtocol(String)

    /// The content type string is invalid.
    case invalidContentType(String)
}

/// Parse a protocol string from CLI into a ProtocolMode.
///
/// Accepts: `"auto"`, `"icecast-put"`, `"icecast-source"`,
/// `"shoutcast-v1"`, `"shoutcast-v2:N"`.
///
/// - Parameter string: The protocol string to parse.
/// - Returns: The corresponding `ProtocolMode`.
/// - Throws: ``CLIParseError/invalidProtocol(_:)`` if the string is invalid.
public func parseProtocolMode(_ string: String) throws -> ProtocolMode {
    switch string.lowercased() {
    case "auto":
        return .auto
    case "icecast-put":
        return .icecastPUT
    case "icecast-source":
        return .icecastSOURCE
    case "shoutcast-v1":
        return .shoutcastV1
    default:
        let lowered = string.lowercased()
        if lowered.hasPrefix("shoutcast-v2:") {
            let idPart = string.dropFirst("shoutcast-v2:".count)
            if let streamId = Int(idPart) {
                return .shoutcastV2(streamId: streamId)
            }
        }
        throw CLIParseError.invalidProtocol(string)
    }
}

/// Parse a content type string from CLI into an AudioContentType.
///
/// Accepts: `"mp3"`, `"aac"`, `"ogg-vorbis"`, `"ogg-opus"`.
///
/// - Parameter string: The content type string to parse.
/// - Returns: The corresponding `AudioContentType`.
/// - Throws: ``CLIParseError/invalidContentType(_:)`` if the string is invalid.
public func parseContentType(_ string: String) throws -> AudioContentType {
    switch string.lowercased() {
    case "mp3":
        return .mp3
    case "aac":
        return .aac
    case "ogg-vorbis":
        return .oggVorbis
    case "ogg-opus":
        return .oggOpus
    default:
        throw CLIParseError.invalidContentType(string)
    }
}
