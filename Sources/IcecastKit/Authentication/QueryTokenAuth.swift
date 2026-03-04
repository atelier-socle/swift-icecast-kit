// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Appends a query token parameter to a mountpoint or URL path.
///
/// Used for servers that authenticate via URL query parameters
/// (e.g. `?key=secret_token`) rather than HTTP headers.
struct QueryTokenAuth: Sendable {

    /// The query parameter key.
    let key: String

    /// The query parameter value.
    let value: String

    /// Returns the mountpoint with `?key=value` or `&key=value` appended.
    ///
    /// If the mountpoint already contains a query string (has `?`),
    /// the parameter is appended with `&`. Otherwise `?` is used.
    /// Special characters in the value are percent-encoded.
    ///
    /// - Parameter mountpoint: The original mountpoint path (e.g. `"/live.mp3"`).
    /// - Returns: The mountpoint with the query token appended.
    func apply(to mountpoint: String) -> String {
        let encodedValue = percentEncode(value)
        let separator = mountpoint.contains("?") ? "&" : "?"
        return "\(mountpoint)\(separator)\(key)=\(encodedValue)"
    }

    // MARK: - Private

    /// Percent-encodes a string for safe inclusion in a URL query parameter.
    private func percentEncode(_ string: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(
            CharacterSet(charactersIn: "&=+")
        )
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
