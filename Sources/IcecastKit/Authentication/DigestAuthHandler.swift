// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Parsed components of an HTTP Digest Authentication challenge.
///
/// Represents the parameters extracted from a `WWW-Authenticate: Digest ...`
/// response header, as defined in RFC 7616.
struct DigestChallenge: Sendable, Hashable {

    /// The protection realm.
    let realm: String

    /// The server-generated nonce value.
    let nonce: String

    /// The hash algorithm to use.
    let algorithm: DigestAlgorithm

    /// The quality of protection directive (e.g. `"auth"`).
    let qop: String?

    /// An opaque value passed back to the server unchanged.
    let opaque: String?

    /// Hash algorithms supported by Digest Authentication.
    enum DigestAlgorithm: String, Sendable, Hashable {
        /// MD5 algorithm (default per RFC 7616).
        case md5 = "MD5"
        /// SHA-256 algorithm.
        case sha256 = "SHA-256"
    }
}

/// Handles RFC 7616 HTTP Digest Authentication challenge/response flow.
///
/// Parses `WWW-Authenticate: Digest` challenge headers and computes
/// the corresponding `Authorization: Digest` response using MD5 or SHA-256.
struct DigestAuthHandler: Sendable {

    /// The username for authentication.
    let username: String

    /// The password for authentication.
    let password: String

    /// Parses a `WWW-Authenticate` header value into a ``DigestChallenge``.
    ///
    /// Returns `nil` if the header does not start with `"Digest "` or
    /// is missing required `realm` or `nonce` parameters.
    ///
    /// - Parameter headerValue: The full `WWW-Authenticate` header value.
    /// - Returns: A parsed ``DigestChallenge``, or `nil` if not a valid Digest challenge.
    func parseChallenge(_ headerValue: String) -> DigestChallenge? {
        let trimmed = headerValue.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("digest ") else { return nil }

        let paramString = String(trimmed.dropFirst("digest ".count))
        let params = parseParameters(paramString)

        guard let realm = params["realm"], let nonce = params["nonce"] else {
            return nil
        }

        let algorithmString = params["algorithm"] ?? "MD5"
        let algorithm: DigestChallenge.DigestAlgorithm
        switch algorithmString.uppercased() {
        case "SHA-256":
            algorithm = .sha256
        default:
            algorithm = .md5
        }

        return DigestChallenge(
            realm: realm,
            nonce: nonce,
            algorithm: algorithm,
            qop: params["qop"],
            opaque: params["opaque"]
        )
    }

    /// Computes the `Authorization: Digest` header value for a given challenge.
    ///
    /// Implements the RFC 7616 digest response calculation:
    /// - Without QoP: `response = hash(HA1:nonce:HA2)`
    /// - With QoP `auth`: `response = hash(HA1:nonce:nc:cnonce:qop:HA2)`
    ///
    /// - Parameters:
    ///   - challenge: The parsed server challenge.
    ///   - method: The HTTP method (e.g. `"PUT"`, `"SOURCE"`, `"GET"`).
    ///   - uri: The request URI (e.g. `"/live.mp3"`).
    /// - Returns: The complete `Authorization` header value.
    func authorizationHeader(
        for challenge: DigestChallenge,
        method: String,
        uri: String
    ) -> String {
        authorizationHeader(
            for: challenge,
            method: method,
            uri: uri,
            cnonce: generateCnonce()
        )
    }

    /// Computes the `Authorization: Digest` header value with a specified cnonce.
    ///
    /// Internal variant that accepts a cnonce for deterministic testing.
    ///
    /// - Parameters:
    ///   - challenge: The parsed server challenge.
    ///   - method: The HTTP method.
    ///   - uri: The request URI.
    ///   - cnonce: The client nonce value.
    /// - Returns: The complete `Authorization` header value.
    func authorizationHeader(
        for challenge: DigestChallenge,
        method: String,
        uri: String,
        cnonce: String
    ) -> String {
        let hash = hashFunction(for: challenge.algorithm)

        let ha1 = hash("\(username):\(challenge.realm):\(password)")
        let ha2 = hash("\(method):\(uri)")

        let response: String
        let nc = "00000001"

        if let qop = challenge.qop, qop.contains("auth") {
            response = hash("\(ha1):\(challenge.nonce):\(nc):\(cnonce):\(qop):\(ha2)")
        } else {
            response = hash("\(ha1):\(challenge.nonce):\(ha2)")
        }

        var header = "Digest "
        header += "username=\"\(username)\", "
        header += "realm=\"\(challenge.realm)\", "
        header += "nonce=\"\(challenge.nonce)\", "
        header += "uri=\"\(uri)\", "
        header += "algorithm=\(challenge.algorithm.rawValue), "

        if let qop = challenge.qop, qop.contains("auth") {
            header += "qop=auth, "
            header += "nc=\(nc), "
            header += "cnonce=\"\(cnonce)\", "
        }

        header += "response=\"\(response)\""

        if let opaque = challenge.opaque {
            header += ", opaque=\"\(opaque)\""
        }

        return header
    }

    // MARK: - Private

    /// Returns the appropriate hash function for the given algorithm.
    private func hashFunction(
        for algorithm: DigestChallenge.DigestAlgorithm
    ) -> (String) -> String {
        switch algorithm {
        case .md5:
            return AuthCrypto.md5
        case .sha256:
            return AuthCrypto.sha256
        }
    }

    /// Generates a random client nonce as a hex string.
    private func generateCnonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<bytes.count {
            bytes[i] = UInt8.random(in: 0...255)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Parses a comma-separated parameter string into a dictionary.
    ///
    /// Handles both quoted and unquoted values:
    /// `realm="test", nonce="abc123", qop=auth`
    private func parseParameters(_ string: String) -> [String: String] {
        var params: [String: String] = [:]
        var remaining = string[string.startIndex...]

        while !remaining.isEmpty {
            remaining = remaining.drop(while: { $0 == " " || $0 == "," })
            guard !remaining.isEmpty else { break }

            guard let equalsIndex = remaining.firstIndex(of: "=") else { break }
            let key = String(remaining[..<equalsIndex])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            remaining = remaining[remaining.index(after: equalsIndex)...]

            if remaining.first == "\"" {
                remaining = remaining.dropFirst()
                if let closeQuote = remaining.firstIndex(of: "\"") {
                    let value = String(remaining[..<closeQuote])
                    params[key] = value
                    remaining = remaining[remaining.index(after: closeQuote)...]
                } else {
                    let value = String(remaining)
                    params[key] = value
                    break
                }
            } else {
                let endIndex = remaining.firstIndex(of: ",") ?? remaining.endIndex
                let value = String(remaining[..<endIndex])
                    .trimmingCharacters(in: .whitespaces)
                params[key] = value
                remaining = remaining[endIndex...]
            }
        }

        return params
    }
}
