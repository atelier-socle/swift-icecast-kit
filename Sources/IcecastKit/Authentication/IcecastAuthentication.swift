// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Authentication mechanisms for connecting to Icecast and SHOUTcast servers.
///
/// Extends beyond HTTP Basic Auth (0.1.0) to support Digest Auth (RFC 7616),
/// Bearer tokens, URL query tokens, and URL-embedded credentials.
///
/// Usage:
/// ```swift
/// // Bearer token
/// let config = IcecastConfiguration(
///     host: "radio.example.com",
///     mountpoint: "/live.mp3",
///     authentication: .bearer(token: "my-api-token")
/// )
///
/// // Digest auth
/// let config = IcecastConfiguration(
///     host: "radio.example.com",
///     mountpoint: "/live.mp3",
///     authentication: .digest(username: "source", password: "hackme")
/// )
///
/// // Parse from URL with embedded credentials
/// if let auth = IcecastAuthentication.fromURL("http://user:pass@host:8000/live.mp3") {
///     // auth == .basic(username: "user", password: "pass")
/// }
/// ```
public enum IcecastAuthentication: Sendable, Hashable, Codable {

    /// HTTP Basic Auth — username:password Base64 encoded.
    ///
    /// Corresponds to existing `IcecastCredentials` behavior in 0.1.0.
    case basic(username: String, password: String)

    /// HTTP Digest Auth per RFC 7616 — challenge/response, no plaintext password.
    ///
    /// On first request, if the server responds with 401 and a
    /// `WWW-Authenticate: Digest` challenge, the client automatically
    /// computes the digest response and retries.
    case digest(username: String, password: String)

    /// `Authorization: Bearer <token>` — token-based authentication.
    case bearer(token: String)

    /// Appends `?key=value` to the request URL / mountpoint.
    case queryToken(key: String, value: String)

    /// SHOUTcast v1 password-only auth.
    case shoutcast(password: String)

    /// SHOUTcast v2 with stream ID.
    case shoutcastV2(password: String, streamId: Int)
}

// MARK: - URL Credential Parsing

extension IcecastAuthentication {

    /// Parses credentials from a URL string containing embedded user info.
    ///
    /// Extracts the `username:password` from URLs of the form
    /// `"https://user:password@host:port/mountpoint"` and returns
    /// a `.basic` authentication value.
    ///
    /// - Parameter urlString: The URL string to parse.
    /// - Returns: A `.basic` authentication value, or `nil` if no credentials are present.
    public static func fromURL(_ urlString: String) -> IcecastAuthentication? {
        guard let components = URLComponents(string: urlString) else { return nil }
        guard let password = components.password, !password.isEmpty else { return nil }
        let rawUser = components.user ?? ""
        let username = rawUser.isEmpty ? "source" : rawUser
        return .basic(username: username, password: password)
    }

    /// Returns the URL with credentials stripped (for use as the actual request URL).
    ///
    /// Removes the `user:password@` portion from the URL if present.
    /// If no credentials are present, returns the URL unchanged.
    ///
    /// - Parameter urlString: The URL string to strip.
    /// - Returns: The URL string without embedded credentials.
    public static func stripCredentials(from urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else { return urlString }
        guard components.user != nil || components.password != nil else { return urlString }
        components.user = nil
        components.password = nil
        return components.string ?? urlString
    }
}

// MARK: - Credential Bridge

extension IcecastAuthentication {

    /// Converts to ``IcecastCredentials`` for backward compatibility.
    ///
    /// Returns `nil` for authentication types that don't map to simple
    /// username/password credentials (`.bearer` and `.queryToken`).
    public var credentials: IcecastCredentials? {
        switch self {
        case .basic(let username, let password):
            return IcecastCredentials(username: username, password: password)
        case .digest(let username, let password):
            return IcecastCredentials(username: username, password: password)
        case .shoutcast(let password):
            return .shoutcast(password: password)
        case .shoutcastV2(let password, let streamId):
            return .shoutcastV2(password: password, streamId: streamId)
        case .bearer, .queryToken:
            return nil
        }
    }

    /// Returns the `Authorization` header value for the initial request.
    ///
    /// - `.basic` → `"Basic <base64>"`
    /// - `.bearer` → `"Bearer <token>"`
    /// - `.digest` → `nil` (requires challenge/response flow)
    /// - `.queryToken` → `nil` (applied to URL, not header)
    /// - `.shoutcast*` → `nil` (uses separate protocol flow)
    func initialAuthorizationHeader() -> String? {
        switch self {
        case .basic(let username, let password):
            let creds = IcecastCredentials(username: username, password: password)
            return creds.basicAuthHeaderValue()
        case .bearer(let token):
            return BearerTokenAuth(token: token).authorizationHeaderValue
        case .digest, .queryToken, .shoutcast, .shoutcastV2:
            return nil
        }
    }
}

// MARK: - IcecastCredentials Bridge

extension IcecastCredentials {

    /// Converts to an ``IcecastAuthentication`` value.
    ///
    /// Returns `.basic` with the credentials' username and password.
    public var authentication: IcecastAuthentication {
        .basic(username: username, password: password)
    }
}
