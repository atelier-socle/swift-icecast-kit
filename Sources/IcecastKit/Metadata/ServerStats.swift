// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Global Icecast server statistics from the admin API.
public struct ServerStats: Sendable, Hashable {

    /// The server version string (e.g., "Icecast 2.5.0").
    public var serverVersion: String

    /// List of active mountpoint paths.
    public var activeMountpoints: [String]

    /// Total number of listeners across all mountpoints.
    public var totalListeners: Int

    /// Total number of active sources.
    public var totalSources: Int

    /// Creates server statistics with the given values.
    ///
    /// - Parameters:
    ///   - serverVersion: The server version string. Defaults to `""`.
    ///   - activeMountpoints: Active mountpoint paths. Defaults to `[]`.
    ///   - totalListeners: Total listener count. Defaults to `0`.
    ///   - totalSources: Total source count. Defaults to `0`.
    public init(
        serverVersion: String = "",
        activeMountpoints: [String] = [],
        totalListeners: Int = 0,
        totalSources: Int = 0
    ) {
        self.serverVersion = serverVersion
        self.activeMountpoints = activeMountpoints
        self.totalListeners = totalListeners
        self.totalSources = totalSources
    }
}

/// Statistics for a specific mountpoint from the admin API.
public struct MountStats: Sendable, Hashable {

    /// The mountpoint path (e.g., "/live.mp3").
    public var mountpoint: String

    /// The number of listeners on this mountpoint.
    public var listeners: Int

    /// The current stream title.
    public var streamTitle: String?

    /// The audio bitrate in kbps.
    public var bitrate: Int?

    /// The stream genre.
    public var genre: String?

    /// The content type (MIME type) of the stream.
    public var contentType: String?

    /// How long the source has been connected, in seconds.
    public var connectedDuration: TimeInterval?

    /// Creates mountpoint statistics with the given values.
    ///
    /// - Parameters:
    ///   - mountpoint: The mountpoint path.
    ///   - listeners: The listener count. Defaults to `0`.
    ///   - streamTitle: The stream title.
    ///   - bitrate: The bitrate in kbps.
    ///   - genre: The stream genre.
    ///   - contentType: The content type string.
    ///   - connectedDuration: Connected duration in seconds.
    public init(
        mountpoint: String,
        listeners: Int = 0,
        streamTitle: String? = nil,
        bitrate: Int? = nil,
        genre: String? = nil,
        contentType: String? = nil,
        connectedDuration: TimeInterval? = nil
    ) {
        self.mountpoint = mountpoint
        self.listeners = listeners
        self.streamTitle = streamTitle
        self.bitrate = bitrate
        self.genre = genre
        self.contentType = contentType
        self.connectedDuration = connectedDuration
    }
}
