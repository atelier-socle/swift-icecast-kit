// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import IcecastKit

/// Errors that can occur when parsing CLI arguments.
public enum CLIParseError: Error, Sendable {

    /// The protocol mode string is invalid.
    case invalidProtocol(String)

    /// The content type string is invalid.
    case invalidContentType(String)

    /// The destination string is invalid.
    case invalidDestination(String)

    /// The authentication type string is invalid.
    case invalidAuthType(String)

    /// A required option is missing for the chosen auth type.
    case missingRequiredOption(String)
}

/// Parsed destination from a CLI `--dest` argument.
public struct ParsedDestination: Sendable {

    /// The destination label.
    public let label: String

    /// The server hostname.
    public let host: String

    /// The server port.
    public let port: Int

    /// The mountpoint path.
    public let mountpoint: String

    /// The authentication password.
    public let password: String

    /// The protocol mode string, if specified.
    public let protocolString: String?
}

/// Parse a `--dest` argument string into a ``ParsedDestination``.
///
/// Format: `label:host:port:mountpoint:password[:protocol]`
///
/// - Parameter string: The destination string to parse.
/// - Returns: A ``ParsedDestination`` with the parsed values.
/// - Throws: ``CLIParseError/invalidDestination(_:)`` if the format is invalid.
public func parseDestination(_ string: String) throws -> ParsedDestination {
    let parts = string.split(separator: ":", maxSplits: 5).map(String.init)
    guard parts.count >= 5 else {
        throw CLIParseError.invalidDestination(
            "Expected format label:host:port:mountpoint:password[:protocol], got: \(string)"
        )
    }
    guard let port = Int(parts[2]) else {
        throw CLIParseError.invalidDestination(
            "Invalid port '\(parts[2])' in destination: \(string)"
        )
    }
    let mountpoint = parts[3].hasPrefix("/") ? parts[3] : "/\(parts[3])"
    let protocolString = parts.count > 5 ? parts[5] : nil

    return ParsedDestination(
        label: parts[0],
        host: parts[1],
        port: port,
        mountpoint: mountpoint,
        password: parts[4],
        protocolString: protocolString
    )
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

/// Resolve an `IcecastAuthentication` from CLI `--auth-type` and `--token` options.
///
/// - Parameters:
///   - authType: The auth type string (basic, digest, bearer, query-token).
///   - username: The username (used for basic/digest).
///   - password: The password (used for basic/digest).
///   - token: The token value (used for bearer/query-token).
/// - Returns: The resolved `IcecastAuthentication`.
/// - Throws: ``CLIParseError`` if the auth type is invalid or required options are missing.
public func resolveAuthentication(
    authType: String,
    username: String,
    password: String?,
    token: String?
) throws -> IcecastAuthentication {
    switch authType.lowercased() {
    case "basic":
        guard let password, !password.isEmpty else {
            throw CLIParseError.missingRequiredOption(
                "--password is required with --auth-type basic"
            )
        }
        return .basic(username: username, password: password)
    case "digest":
        guard let password, !password.isEmpty else {
            throw CLIParseError.missingRequiredOption(
                "--password is required with --auth-type digest"
            )
        }
        return .digest(username: username, password: password)
    case "bearer":
        guard let token, !token.isEmpty else {
            throw CLIParseError.missingRequiredOption(
                "--token is required with --auth-type bearer"
            )
        }
        return .bearer(token: token)
    case "query-token":
        guard let token, !token.isEmpty else {
            throw CLIParseError.missingRequiredOption(
                "--token is required with --auth-type query-token"
            )
        }
        return .queryToken(key: "token", value: token)
    default:
        throw CLIParseError.invalidAuthType(authType)
    }
}
