// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

extension String {

    /// Encodes the string for use in URL query parameters.
    ///
    /// - Returns: A percent-encoded string safe for URL query parameters.
    func icyURLEncoded() -> String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }

    /// Escapes single quotes for ICY metadata values.
    ///
    /// ICY metadata values use single quotes as delimiters, so literal
    /// single quotes in the value must be escaped by doubling them.
    ///
    /// - Returns: The string with single quotes escaped.
    func icySingleQuoteEscaped() -> String {
        replacingOccurrences(of: "'", with: "''")
    }

    /// Encodes the string as Base64 using UTF-8 encoding.
    ///
    /// - Returns: A Base64-encoded string, or `nil` if UTF-8 encoding fails.
    func base64Encoded() -> String? {
        data(using: .utf8)?.base64EncodedString()
    }

    /// Converts the string to `Data` using UTF-8 encoding.
    ///
    /// - Returns: UTF-8 encoded data, or `nil` if encoding fails.
    func toUTF8Data() -> Data? {
        data(using: .utf8)
    }

    /// Encodes the string for use in a URL path component.
    ///
    /// - Returns: A percent-encoded string safe for URL paths.
    func icyPathEncoded() -> String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
