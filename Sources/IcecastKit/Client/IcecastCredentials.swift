// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Credentials used to authenticate with an Icecast or SHOUTcast server.
///
/// For Icecast, the default username is `"source"`. For SHOUTcast v1,
/// only the password is used. For SHOUTcast v2, the stream ID is encoded
/// in the username.
public struct IcecastCredentials: Sendable, Hashable, Codable {

    /// The username for authentication. Defaults to `"source"` for Icecast.
    public var username: String

    /// The password for authentication.
    public var password: String

    /// Creates credentials with the given username and password.
    ///
    /// - Parameters:
    ///   - username: The authentication username. Defaults to `"source"`.
    ///   - password: The authentication password.
    public init(username: String = "source", password: String) {
        self.username = username
        self.password = password
    }

    /// Creates credentials for SHOUTcast v1 authentication.
    ///
    /// SHOUTcast v1 uses only a password (no username).
    ///
    /// - Parameter password: The SHOUTcast password.
    /// - Returns: Credentials configured for SHOUTcast v1.
    public static func shoutcast(password: String) -> IcecastCredentials {
        IcecastCredentials(username: "", password: password)
    }

    /// Creates credentials for SHOUTcast v2 authentication.
    ///
    /// SHOUTcast v2 encodes the stream ID in the username.
    ///
    /// - Parameters:
    ///   - password: The SHOUTcast password.
    ///   - streamId: The stream identifier.
    /// - Returns: Credentials configured for SHOUTcast v2.
    public static func shoutcastV2(password: String, streamId: Int) -> IcecastCredentials {
        IcecastCredentials(username: "sid=\(streamId)", password: password)
    }

    /// Generates the HTTP Basic Authentication header value.
    ///
    /// Encodes `"username:password"` as Base64 and prepends `"Basic "`.
    ///
    /// - Returns: The complete `Authorization` header value.
    public func basicAuthHeaderValue() -> String {
        let credentials = "\(username):\(password)"
        let base64 = Data(credentials.utf8).base64EncodedString()
        return "Basic \(base64)"
    }
}
