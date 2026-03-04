// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

// MARK: - Preset Metadata

extension IcecastServerPreset {

    /// Human-readable name of the platform.
    public var displayName: String {
        switch self {
        case .azuracast: "AzuraCast"
        case .libretime: "LibreTime"
        case .radioCo: "Radio.co"
        case .centovaCast: "Centova Cast"
        case .shoutcastDNAS: "SHOUTcast DNAS"
        case .icecastOfficial: "Icecast"
        case .broadcastify: "Broadcastify"
        }
    }

    /// Brief description of the platform and its typical use case.
    public var presetDescription: String {
        switch self {
        case .azuracast:
            "Self-hosted web radio management suite with built-in Icecast/SHOUTcast support"
        case .libretime:
            "Open-source radio automation platform for community radio stations"
        case .radioCo:
            "Cloud-based radio hosting platform with API token authentication"
        case .centovaCast:
            "Panel-managed SHOUTcast hosting with web-based administration"
        case .shoutcastDNAS:
            "Official Nullsoft/Radionomy DNAS streaming server"
        case .icecastOfficial:
            "Vanilla Icecast 2.4+/2.5.x open-source streaming media server"
        case .broadcastify:
            "Emergency services and scanner feed streaming platform"
        }
    }

    /// Default port for this preset.
    public var defaultPort: Int {
        switch self {
        case .broadcastify: 80
        case .azuracast, .libretime, .radioCo,
            .centovaCast, .shoutcastDNAS, .icecastOfficial:
            8000
        }
    }

    /// Default mountpoint pattern (e.g. `"/radio.mp3"`, `"/"`).
    public var defaultMountpoint: String {
        switch self {
        case .azuracast: "/radio.mp3"
        case .libretime: "/main.mp3"
        case .radioCo: "/live.mp3"
        case .centovaCast: "/stream.mp3"
        case .shoutcastDNAS: "/"
        case .icecastOfficial: "/stream.mp3"
        case .broadcastify: "/stream.mp3"
        }
    }

    /// Protocol dialect used by this preset.
    public var protocolMode: ProtocolMode {
        switch self {
        case .azuracast, .libretime, .radioCo,
            .icecastOfficial, .broadcastify:
            .icecastPUT
        case .centovaCast:
            .shoutcastV2(streamId: 1)
        case .shoutcastDNAS:
            .shoutcastV1
        }
    }

    /// Authentication mechanism used by this preset.
    public var authenticationStyle: PresetAuthStyle {
        switch self {
        case .azuracast, .libretime, .icecastOfficial:
            .basicAuth
        case .radioCo, .broadcastify:
            .bearerToken
        case .centovaCast:
            .shoutcastV2
        case .shoutcastDNAS:
            .passwordOnly
        }
    }
}

// MARK: - Configuration Factory

extension IcecastServerPreset {

    /// Creates a fully configured ``IcecastConfiguration`` for this preset.
    ///
    /// The preset provides all platform-specific defaults (port, mountpoint,
    /// protocol, authentication). You only supply the variable parameters.
    ///
    /// - Parameters:
    ///   - host: Server hostname (e.g. `"mystation.azuracast.com"`).
    ///   - port: Override the default port. `nil` uses the preset default.
    ///   - mountpoint: Override the default mountpoint. `nil` uses the preset default.
    ///   - password: Source/DJ password for authentication.
    ///   - contentType: Audio content type. Defaults to `.mp3`.
    /// - Returns: A fully configured ``IcecastConfiguration``.
    public func configuration(
        host: String,
        port: Int? = nil,
        mountpoint: String? = nil,
        password: String,
        contentType: AudioContentType = .mp3
    ) -> IcecastConfiguration {
        let effectivePort = port ?? defaultPort
        let effectiveMountpoint = mountpoint ?? defaultMountpoint

        var config = IcecastConfiguration(
            host: host,
            port: effectivePort,
            mountpoint: effectiveMountpoint,
            contentType: contentType,
            protocolMode: protocolMode
        )

        applyAuthentication(
            to: &config, password: password
        )

        return config
    }

    /// Applies this preset's settings to an existing configuration.
    ///
    /// Modifies the port (only if still at the default value of 8000),
    /// protocol mode, and authentication style. Does not modify host,
    /// mountpoint, content type, or the credentials password value.
    ///
    /// - Parameter configuration: The configuration to modify in place.
    public func apply(to configuration: inout IcecastConfiguration) {
        if configuration.port == 8000 {
            configuration.port = defaultPort
        }

        configuration.protocolMode = protocolMode

        let password =
            configuration.credentials?.password
            ?? configuration.authentication?.extractPassword ?? ""

        applyAuthentication(to: &configuration, password: password)
    }

    /// Sets credentials and authentication on a configuration for the given password.
    private func applyAuthentication(
        to config: inout IcecastConfiguration,
        password: String
    ) {
        switch authenticationStyle {
        case .basicAuth:
            config.credentials = IcecastCredentials(
                username: "source", password: password
            )
            config.authentication = .basic(
                username: "source", password: password
            )
        case .passwordOnly:
            config.credentials = .shoutcast(password: password)
            config.authentication = .shoutcast(password: password)
        case .shoutcastV2:
            config.credentials = .shoutcastV2(
                password: password, streamId: 1
            )
            config.authentication = .shoutcastV2(
                password: password, streamId: 1
            )
        case .bearerToken:
            config.authentication = .bearer(token: password)
        }
    }
}

// MARK: - Authentication Password Extraction

extension IcecastAuthentication {

    /// Extracts the password from an authentication value, if available.
    var extractPassword: String? {
        switch self {
        case .basic(_, let password),
            .digest(_, let password),
            .shoutcast(let password):
            password
        case .shoutcastV2(let password, _):
            password
        case .bearer(let token):
            token
        case .queryToken:
            nil
        }
    }
}
