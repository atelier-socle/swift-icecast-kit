// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// Cross-platform cryptographic helpers for authentication.
///
/// Uses `CryptoKit` on Apple platforms and `swift-crypto` on Linux.
/// Provides MD5 (for Digest Auth backward compatibility) and SHA-256 hashing.
enum AuthCrypto {

    /// Computes the MD5 hash of a UTF-8 string and returns a lowercase hex string.
    ///
    /// Used for HTTP Digest Authentication with `algorithm=MD5`.
    ///
    /// - Parameter string: The input string to hash.
    /// - Returns: A 32-character lowercase hexadecimal string.
    static func md5(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes the SHA-256 hash of a UTF-8 string and returns a lowercase hex string.
    ///
    /// Used for HTTP Digest Authentication with `algorithm=SHA-256`.
    ///
    /// - Parameter string: The input string to hash.
    /// - Returns: A 64-character lowercase hexadecimal string.
    static func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
