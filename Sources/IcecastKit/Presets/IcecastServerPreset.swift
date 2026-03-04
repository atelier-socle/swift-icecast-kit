// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Authentication style used by a server preset.
///
/// Indicates the type of authentication mechanism a server platform expects.
public enum PresetAuthStyle: String, Sendable, CaseIterable, Codable {

    /// Standard HTTP Basic (username:password).
    case basicAuth

    /// Password only (no username) — SHOUTcast v1.
    case passwordOnly

    /// SHOUTcast v2 with stream IDs.
    case shoutcastV2

    /// Authorization: Bearer — token-based auth.
    case bearerToken
}

/// Preconfigured settings for popular streaming server platforms.
///
/// Each preset encapsulates the default port, mountpoint, protocol dialect,
/// and authentication mechanism for a specific platform. The consumer
/// provides only the variable parameters (host, password, optional mountpoint
/// override), and the preset handles the rest.
///
/// Usage:
/// ```swift
/// let config = IcecastServerPreset.azuracast.configuration(
///     host: "mystation.azuracast.com",
///     password: "my-source-password"
/// )
/// ```
public enum IcecastServerPreset: String, Sendable, CaseIterable, Codable {

    /// AzuraCast — self-hosted web radio management suite.
    case azuracast

    /// LibreTime — open-source radio automation (ex-Airtime).
    case libretime

    /// Radio.co — cloud radio platform with API token auth.
    case radioCo

    /// Centova Cast — panel-managed SHOUTcast hosting.
    case centovaCast

    /// SHOUTcast DNAS — official Nullsoft/Radionomy server.
    case shoutcastDNAS

    /// Icecast — vanilla Icecast 2.4+/2.5.x server.
    case icecastOfficial

    /// Broadcastify — emergency/scanner feed platform.
    case broadcastify
}
