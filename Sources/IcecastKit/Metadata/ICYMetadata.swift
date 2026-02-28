// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Represents ICY (Icecast/SHOUTcast) stream metadata.
///
/// The ICY metadata protocol uses `key='value';` pairs embedded in the audio stream.
/// `StreamTitle` is universally supported by players; `StreamUrl` has inconsistent support.
public struct ICYMetadata: Sendable, Hashable, Codable {

    /// The stream title, typically "Artist - Song Title".
    public var streamTitle: String?

    /// Optional stream URL.
    public var streamUrl: String?

    /// Custom metadata fields beyond StreamTitle and StreamUrl.
    public var customFields: [String: String]

    /// Creates ICY metadata with the given fields.
    ///
    /// - Parameters:
    ///   - streamTitle: The stream title.
    ///   - streamUrl: An optional stream URL.
    ///   - customFields: Additional custom metadata fields.
    public init(
        streamTitle: String? = nil,
        streamUrl: String? = nil,
        customFields: [String: String] = [:]
    ) {
        self.streamTitle = streamTitle
        self.streamUrl = streamUrl
        self.customFields = customFields
    }

    /// Whether this metadata contains no fields.
    public var isEmpty: Bool {
        streamTitle == nil && streamUrl == nil && customFields.isEmpty
    }

    /// URL-encoded song string for the admin API `song` parameter.
    ///
    /// Returns the `streamTitle` percent-encoded for use in the admin API
    /// query string (`/admin/metadata?song=...`). Spaces become `+`,
    /// special characters are percent-encoded.
    ///
    /// - Returns: The URL-encoded song string, or `nil` if `streamTitle` is `nil`.
    public func urlEncodedSong() -> String? {
        guard let title = streamTitle else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")
        return
            title
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+")
    }
}
