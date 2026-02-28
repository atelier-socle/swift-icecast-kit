// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Builds raw HTTP request bytes for Icecast and SHOUTcast protocols.
///
/// Supports Icecast HTTP PUT (modern), Icecast SOURCE (legacy),
/// and SHOUTcast v1 authentication and headers.
public struct HTTPRequestBuilder: Sendable {

    /// The User-Agent string sent with all requests.
    static let userAgent = "IcecastKit/0.1.0"

    /// Creates a new HTTP request builder.
    public init() {}

    /// Builds an Icecast HTTP PUT request (modern, since 2.4.0).
    ///
    /// This is the preferred method for Icecast 2.4+ servers. The request
    /// includes `Expect: 100-continue` and all ice-* station headers.
    ///
    /// - Parameters:
    ///   - mountpoint: The mount path (e.g., `"/live.mp3"`).
    ///   - credentials: Authentication credentials.
    ///   - host: The server hostname.
    ///   - port: The server port.
    ///   - contentType: The audio content type.
    ///   - stationInfo: Station metadata for ice-* headers.
    /// - Returns: The raw HTTP request bytes ready to send.
    public func buildIcecastPUT(
        mountpoint: String,
        credentials: IcecastCredentials,
        host: String,
        port: Int,
        contentType: AudioContentType,
        stationInfo: StationInfo
    ) -> Data {
        var lines: [String] = []

        lines.append("PUT \(mountpoint) HTTP/1.1")
        lines.append("Host: \(host):\(port)")
        lines.append("Authorization: \(credentials.basicAuthHeaderValue())")
        lines.append("Content-Type: \(contentType.rawValue)")
        lines.append("User-Agent: \(Self.userAgent)")
        lines.append("Expect: 100-continue")

        appendIceHeaders(to: &lines, stationInfo: stationInfo)

        lines.append("")
        lines.append("")

        let request = lines.joined(separator: "\r\n")
        return Data(request.utf8)
    }

    /// Builds an Icecast SOURCE request (legacy, pre-2.4.0).
    ///
    /// Uses the `SOURCE` method with `ICE/1.0` protocol version.
    /// This format is used by older Icecast servers that don't support HTTP PUT.
    ///
    /// - Parameters:
    ///   - mountpoint: The mount path (e.g., `"/live.mp3"`).
    ///   - credentials: Authentication credentials.
    ///   - contentType: The audio content type.
    ///   - stationInfo: Station metadata for ice-* headers.
    /// - Returns: The raw HTTP request bytes ready to send.
    public func buildIcecastSOURCE(
        mountpoint: String,
        credentials: IcecastCredentials,
        contentType: AudioContentType,
        stationInfo: StationInfo
    ) -> Data {
        var lines: [String] = []

        lines.append("SOURCE \(mountpoint) ICE/1.0")
        lines.append("Authorization: \(credentials.basicAuthHeaderValue())")
        lines.append("Content-Type: \(contentType.rawValue)")

        appendIceHeaders(to: &lines, stationInfo: stationInfo)

        lines.append("")
        lines.append("")

        let request = lines.joined(separator: "\r\n")
        return Data(request.utf8)
    }

    /// Builds a SHOUTcast v1 password authentication line.
    ///
    /// SHOUTcast v1 sends the password as the first line after connecting.
    ///
    /// - Parameter password: The SHOUTcast password.
    /// - Returns: The password line as raw bytes.
    public func buildShoutcastV1Auth(password: String) -> Data {
        Data("\(password)\r\n".utf8)
    }

    /// Builds SHOUTcast stream headers sent after receiving OK2.
    ///
    /// These headers configure the stream content type and station metadata
    /// using ICY-prefixed header names.
    ///
    /// - Parameters:
    ///   - contentType: The audio content type.
    ///   - stationInfo: Station metadata for icy-* headers.
    /// - Returns: The raw header bytes ready to send.
    public func buildShoutcastHeaders(
        contentType: AudioContentType,
        stationInfo: StationInfo
    ) -> Data {
        var lines: [String] = []

        lines.append("content-type: \(contentType.rawValue)")

        if let name = stationInfo.name {
            lines.append("icy-name: \(name)")
        }
        if let genre = stationInfo.genre {
            lines.append("icy-genre: \(genre)")
        }
        lines.append("icy-pub: \(stationInfo.isPublic ? 1 : 0)")
        if let bitrate = stationInfo.bitrate {
            lines.append("icy-br: \(bitrate)")
        }

        lines.append("")
        lines.append("")

        let headers = lines.joined(separator: "\r\n")
        return Data(headers.utf8)
    }

    // MARK: - Private

    /// Appends ice-* headers from station info to the request lines.
    private func appendIceHeaders(to lines: inout [String], stationInfo: StationInfo) {
        lines.append("ice-public: \(stationInfo.isPublic ? 1 : 0)")

        if let name = stationInfo.name {
            lines.append("ice-name: \(name)")
        }
        if let description = stationInfo.description {
            lines.append("ice-description: \(description)")
        }
        if let url = stationInfo.url {
            lines.append("ice-url: \(url)")
        }
        if let genre = stationInfo.genre {
            lines.append("ice-genre: \(genre)")
        }
        if let audioInfo = stationInfo.audioInfoHeaderValue() {
            lines.append("ice-audio-info: \(audioInfo)")
        }
    }
}
