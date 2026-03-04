// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Comprehensive error hierarchy for all IcecastKit operations.
///
/// Errors are grouped by category: connection, authentication, protocol,
/// mountpoint, metadata, state, and data errors.
public enum IcecastError: Error, Sendable, Hashable, CustomStringConvertible {

    // MARK: - Connection

    /// TCP connection to the server failed.
    case connectionFailed(host: String, port: Int, reason: String)

    /// Connection attempt timed out.
    case connectionTimeout(seconds: Double)

    /// An established connection was lost unexpectedly.
    case connectionLost(reason: String)

    /// TLS handshake or encryption error.
    case tlsError(reason: String)

    /// DNS resolution failed for the given host.
    case dnsResolutionFailed(host: String)

    // MARK: - Authentication

    /// Server rejected the provided credentials.
    case authenticationFailed(statusCode: Int, message: String)

    /// No credentials were provided but the server requires them.
    case credentialsRequired

    // MARK: - Protocol

    /// All attempted protocol variants failed negotiation.
    case protocolNegotiationFailed(tried: [String])

    /// Server returned an unexpected HTTP status code.
    case unexpectedResponse(statusCode: Int, message: String)

    /// Response data could not be parsed.
    case invalidResponse(reason: String)

    /// Server returned an empty response.
    case emptyResponse

    /// Server returned a 5xx error.
    case serverError(statusCode: Int, message: String)

    // MARK: - Mountpoint

    /// The requested mountpoint is already in use by another source.
    case mountpointInUse(String)

    /// The requested mountpoint does not exist on the server.
    case mountpointNotFound(String)

    /// The server does not support the requested content type.
    case contentTypeNotSupported(String)

    /// The server has reached its maximum number of sources.
    case tooManySources

    /// The mountpoint path is invalid.
    case invalidMountpoint(String)

    // MARK: - Metadata

    /// Metadata string could not be encoded.
    case metadataEncodingFailed(reason: String)

    /// Metadata exceeds the maximum allowed length.
    case metadataTooLong(length: Int, maxLength: Int)

    /// Metadata update request failed.
    case metadataUpdateFailed(reason: String)

    /// The admin API endpoint is not available.
    case adminAPIUnavailable

    // MARK: - State

    /// Operation requires an active connection but none exists.
    case notConnected

    /// A connection is already established.
    case alreadyConnected

    /// Streaming is already in progress.
    case alreadyStreaming

    /// The client is in an invalid state for the requested operation.
    case invalidState(current: String, expected: String)

    // MARK: - Multi-Destination

    /// A destination with the given label already exists.
    case destinationAlreadyExists(label: String)

    /// No destination with the given label was found.
    case destinationNotFound(label: String)

    /// All destinations failed to connect.
    case allDestinationsFailed

    /// Some destinations failed during a multi-destination send.
    case partialSendFailure(successCount: Int, failureCount: Int)

    // MARK: - Probe

    /// Bandwidth probe failed.
    case probeFailed(reason: String)

    /// Bandwidth probe timed out.
    case probeTimeout

    // MARK: - Data

    /// Sending audio data failed.
    case sendFailed(reason: String)

    /// The provided audio data is invalid or corrupt.
    case invalidAudioData(reason: String)

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        // Connection
        case .connectionFailed(let host, let port, let reason):
            return "Connection to \(host):\(port) failed: \(reason)"
        case .connectionTimeout(let seconds):
            return "Connection timed out after \(seconds) seconds"
        case .connectionLost(let reason):
            return "Connection lost: \(reason)"
        case .tlsError(let reason):
            return "TLS error: \(reason)"
        case .dnsResolutionFailed(let host):
            return "DNS resolution failed for host: \(host)"

        // Authentication
        case .authenticationFailed(let statusCode, let message):
            return "Authentication failed (HTTP \(statusCode)): \(message)"
        case .credentialsRequired:
            return "Credentials are required but were not provided"

        // Protocol
        case .protocolNegotiationFailed(let tried):
            return "Protocol negotiation failed, tried: \(tried.joined(separator: ", "))"
        case .unexpectedResponse(let statusCode, let message):
            return "Unexpected response (HTTP \(statusCode)): \(message)"
        case .invalidResponse(let reason):
            return "Invalid response: \(reason)"
        case .emptyResponse:
            return "Server returned an empty response"
        case .serverError(let statusCode, let message):
            return "Server error (HTTP \(statusCode)): \(message)"

        // Mountpoint
        case .mountpointInUse(let mount):
            return "Mountpoint is already in use: \(mount)"
        case .mountpointNotFound(let mount):
            return "Mountpoint not found: \(mount)"
        case .contentTypeNotSupported(let contentType):
            return "Content type not supported: \(contentType)"
        case .tooManySources:
            return "Server has reached the maximum number of sources"
        case .invalidMountpoint(let mount):
            return "Invalid mountpoint: \(mount)"

        // Metadata
        case .metadataEncodingFailed(let reason):
            return "Metadata encoding failed: \(reason)"
        case .metadataTooLong(let length, let maxLength):
            return "Metadata too long (\(length) bytes, max \(maxLength))"
        case .metadataUpdateFailed(let reason):
            return "Metadata update failed: \(reason)"
        case .adminAPIUnavailable:
            return "Admin API is not available on this server"

        // State
        case .notConnected:
            return "Not connected to any server"
        case .alreadyConnected:
            return "Already connected to a server"
        case .alreadyStreaming:
            return "Already streaming to a mountpoint"
        case .invalidState(let current, let expected):
            return "Invalid state: currently \(current), expected \(expected)"

        // Multi-Destination
        case .destinationAlreadyExists(let label):
            return "Destination already exists: \(label)"
        case .destinationNotFound(let label):
            return "Destination not found: \(label)"
        case .allDestinationsFailed:
            return "All destinations failed to connect"
        case .partialSendFailure(let successCount, let failureCount):
            return "Partial send failure: \(successCount) succeeded, \(failureCount) failed"

        // Probe
        case .probeFailed(let reason):
            return "Bandwidth probe failed: \(reason)"
        case .probeTimeout:
            return "Bandwidth probe timed out"

        // Data
        case .sendFailed(let reason):
            return "Send failed: \(reason)"
        case .invalidAudioData(let reason):
            return "Invalid audio data: \(reason)"
        }
    }
}
