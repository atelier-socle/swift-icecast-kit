// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Generates an `Authorization: Bearer` header value.
///
/// Used for token-based authentication with Icecast servers
/// that support OAuth2 or custom bearer token authentication.
struct BearerTokenAuth: Sendable {

    /// The bearer token.
    let token: String

    /// The complete `Authorization` header value: `"Bearer <token>"`.
    var authorizationHeaderValue: String {
        "Bearer \(token)"
    }
}
