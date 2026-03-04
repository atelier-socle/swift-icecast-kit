// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Represents an audio content type (MIME type) for streaming.
///
/// Common audio formats supported by Icecast and SHOUTcast servers.
public struct AudioContentType: RawRepresentable, Sendable, Hashable, Codable, CaseIterable {

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

/// Configuration for connecting to an Icecast/SHOUTcast server.
///
/// Holds all parameters needed to establish a connection and begin streaming,
/// including server address, mountpoint, content type, and protocol variant.
public struct IcecastConfiguration: Sendable, Hashable, Codable {

    /// The server hostname.
    public var host: String

    /// The server port number.
    public var port: Int

    /// The mountpoint path (e.g., `"/live.mp3"`).
    public var mountpoint: String

    /// Whether to use TLS encryption.
    public var useTLS: Bool

    /// The audio content type.
    public var contentType: AudioContentType

    /// Station metadata for ice-* / icy-* headers.
    public var stationInfo: StationInfo

    /// The streaming protocol variant to use.
    public var protocolMode: ProtocolMode

    /// Optional admin credentials for metadata updates.
    public var adminCredentials: IcecastCredentials?

    /// The metadata interval in bytes.
    public var metadataInterval: Int

    /// Adaptive bitrate policy.
    ///
    /// When set, the client instantiates a ``NetworkConditionMonitor``
    /// that measures network conditions and emits ``BitrateRecommendation``
    /// events via the ``ConnectionEvent/bitrateRecommendation(_:)`` event.
    /// Set to `nil` to disable adaptive bitrate (default).
    public var adaptiveBitrate: AdaptiveBitratePolicy?

    /// Authentication credentials for this connection.
    ///
    /// Required for multi-destination use via ``MultiIcecastClient``.
    /// When using ``IcecastClient`` directly, credentials can also be
    /// passed as a separate parameter to the initializer.
    public var credentials: IcecastCredentials?

    /// Reconnection policy for this connection.
    ///
    /// Controls automatic reconnection behavior including retry count,
    /// backoff strategy, and jitter.
    public var reconnectPolicy: ReconnectPolicy

    /// Recording configuration. `nil` = recording disabled.
    ///
    /// When set, the client automatically records audio data to local files
    /// after each successful ``IcecastClient/send(_:)`` call.
    public var recording: RecordingConfiguration?

    /// Advanced authentication method for this connection.
    ///
    /// When set, overrides the `credentials` parameter passed to
    /// ``IcecastClient/init(configuration:credentials:reconnectPolicy:)``.
    /// Supports Bearer tokens, Digest auth, query tokens, and more.
    /// Set to `nil` to use traditional ``IcecastCredentials`` (default).
    public var authentication: IcecastAuthentication?

    /// Creates a new Icecast configuration.
    ///
    /// - Parameters:
    ///   - host: The server hostname.
    ///   - port: The server port. Defaults to `8000`.
    ///   - mountpoint: The mountpoint path.
    ///   - useTLS: Whether to use TLS. Defaults to `false`.
    ///   - contentType: The audio content type. Defaults to `.mp3`.
    ///   - stationInfo: Station metadata. Defaults to empty.
    ///   - protocolMode: The protocol variant. Defaults to `.auto`.
    ///   - adminCredentials: Optional admin credentials.
    ///   - metadataInterval: Metadata interval in bytes. Defaults to `8192`.
    ///   - adaptiveBitrate: Adaptive bitrate policy. Defaults to `nil` (disabled).
    ///   - credentials: Authentication credentials. Defaults to `nil`.
    ///   - reconnectPolicy: Reconnection policy. Defaults to `.default`.
    ///   - recording: Recording configuration. Defaults to `nil` (disabled).
    ///   - authentication: Advanced authentication method. Defaults to `nil`.
    public init(
        host: String,
        port: Int = 8000,
        mountpoint: String,
        useTLS: Bool = false,
        contentType: AudioContentType = .mp3,
        stationInfo: StationInfo = StationInfo(),
        protocolMode: ProtocolMode = .auto,
        adminCredentials: IcecastCredentials? = nil,
        metadataInterval: Int = 8192,
        adaptiveBitrate: AdaptiveBitratePolicy? = nil,
        credentials: IcecastCredentials? = nil,
        reconnectPolicy: ReconnectPolicy = .default,
        recording: RecordingConfiguration? = nil,
        authentication: IcecastAuthentication? = nil
    ) {
        self.host = host
        self.port = port
        self.mountpoint = mountpoint
        self.useTLS = useTLS
        self.contentType = contentType
        self.stationInfo = stationInfo
        self.protocolMode = protocolMode
        self.adminCredentials = adminCredentials
        self.metadataInterval = metadataInterval
        self.adaptiveBitrate = adaptiveBitrate
        self.credentials = credentials
        self.reconnectPolicy = reconnectPolicy
        self.recording = recording
        self.authentication = authentication
    }

    /// Creates a configuration and credentials from a URL string.
    ///
    /// Supported schemes: `icecast://`, `shoutcast://`, `http://`, `https://`
    ///
    /// Format: `scheme://username:password@host:port/mountpoint`
    ///
    /// - Parameter urlString: The URL string to parse.
    /// - Returns: A tuple of the parsed configuration and extracted credentials.
    /// - Throws: ``IcecastError/credentialsRequired`` or ``IcecastError/invalidMountpoint(_:)``.
    public static func from(url urlString: String) throws -> (IcecastConfiguration, IcecastCredentials) {
        let components = try validatedComponents(from: urlString)
        guard let scheme = components.scheme?.lowercased(),
            let host = components.host
        else {
            throw IcecastError.invalidMountpoint("Invalid URL: \(urlString)")
        }
        let isShoutcast = scheme == "shoutcast"

        let mountpoint = components.path.isEmpty ? "/stream" : components.path
        let protocolMode = isShoutcast ? shoutcastMode(from: components) : .auto

        let password = try extractPassword(from: components, isShoutcast: isShoutcast)
        let credentials = buildCredentials(
            password: password, isShoutcast: isShoutcast,
            protocolMode: protocolMode, components: components
        )

        let configuration = IcecastConfiguration(
            host: host,
            port: components.port ?? 8000,
            mountpoint: mountpoint,
            useTLS: scheme == "https",
            contentType: AudioContentType.detect(from: mountpoint) ?? .mp3,
            protocolMode: protocolMode
        )

        return (configuration, credentials)
    }

    // MARK: - URL Parsing Helpers

    /// Validates and returns URL components from a string.
    private static func validatedComponents(from urlString: String) throws -> URLComponents {
        guard let components = URLComponents(string: urlString) else {
            throw IcecastError.invalidMountpoint("Invalid URL: \(urlString)")
        }
        guard let scheme = components.scheme?.lowercased() else {
            throw IcecastError.invalidMountpoint("Missing scheme in URL: \(urlString)")
        }
        guard ["icecast", "shoutcast", "http", "https"].contains(scheme) else {
            throw IcecastError.invalidMountpoint("Unsupported scheme '\(scheme)' in URL: \(urlString)")
        }
        guard let host = components.host, !host.isEmpty else {
            throw IcecastError.invalidMountpoint("Missing host in URL: \(urlString)")
        }
        return components
    }

    /// Determines the SHOUTcast protocol mode from query parameters.
    private static func shoutcastMode(from components: URLComponents) -> ProtocolMode {
        let queryItems = components.queryItems ?? []
        if let streamIdItem = queryItems.first(where: { $0.name == "streamId" }),
            let streamIdValue = streamIdItem.value,
            let streamId = Int(streamIdValue)
        {
            return .shoutcastV2(streamId: streamId)
        }
        return .shoutcastV1
    }

    /// Extracts the password from URL components.
    private static func extractPassword(from components: URLComponents, isShoutcast: Bool) throws -> String {
        if isShoutcast {
            if let pw = components.password, !pw.isEmpty { return pw }
            if let user = components.user, !user.isEmpty { return user }
            throw IcecastError.credentialsRequired
        }
        guard let pw = components.password, !pw.isEmpty else {
            throw IcecastError.credentialsRequired
        }
        return pw
    }

    /// Builds credentials from parsed URL components.
    private static func buildCredentials(
        password: String, isShoutcast: Bool,
        protocolMode: ProtocolMode, components: URLComponents
    ) -> IcecastCredentials {
        if isShoutcast {
            if case .shoutcastV2(let streamId) = protocolMode {
                return .shoutcastV2(password: password, streamId: streamId)
            }
            return .shoutcast(password: password)
        }
        let rawUsername = components.user ?? ""
        let username = rawUsername.isEmpty ? "source" : rawUsername
        return IcecastCredentials(username: username, password: password)
    }

    // MARK: - Auto-Configuration

    /// Creates a configuration with bitrate automatically calibrated via bandwidth probe.
    ///
    /// Runs a bandwidth probe before returning, then selects the optimal bitrate
    /// for the given target quality. The resulting configuration has its
    /// ``stationInfo`` bitrate set to the recommended value.
    ///
    /// - Parameters:
    ///   - host: Server hostname.
    ///   - port: Server port. Defaults to `8000`.
    ///   - mountpoint: Mountpoint for streaming.
    ///   - credentials: Source credentials for authentication.
    ///   - contentType: Audio content type. Defaults to `.mp3`.
    ///   - targetQuality: Quality target for bitrate selection. Defaults to `.balanced`.
    ///   - probeMountpoint: Mountpoint for the probe. Defaults to `mountpoint + "/probe"`.
    ///   - probeDuration: Probe duration in seconds. Defaults to `5.0`.
    /// - Returns: A configured ``IcecastConfiguration`` with calibrated bitrate.
    /// - Throws: ``IcecastError/probeFailed(reason:)`` or ``IcecastError/probeTimeout``.
    public static func autoConfigured(
        host: String,
        port: Int = 8000,
        mountpoint: String,
        credentials: IcecastCredentials,
        contentType: AudioContentType = .mp3,
        targetQuality: ProbeTargetQuality = .balanced,
        probeMountpoint: String? = nil,
        probeDuration: TimeInterval = 5.0
    ) async throws -> IcecastConfiguration {
        let actualProbeMountpoint = probeMountpoint ?? (mountpoint + "/probe")
        let probe = IcecastBandwidthProbe()
        let result = try await probe.measure(
            host: host,
            port: port,
            mountpoint: actualProbeMountpoint,
            credentials: credentials,
            contentType: contentType,
            duration: probeDuration
        )

        let targetBandwidth = result.uploadBandwidth * targetQuality.utilizationFactor
        let step = AudioQualityStep.closestStep(
            for: Int(targetBandwidth), contentType: contentType
        )
        let bitrate = step?.bitrate ?? result.recommendedBitrate
        let bitrateKbps = bitrate / 1000

        return IcecastConfiguration(
            host: host,
            port: port,
            mountpoint: mountpoint,
            contentType: contentType,
            stationInfo: StationInfo(bitrate: bitrateKbps),
            credentials: credentials,
            reconnectPolicy: .default
        )
    }
}
