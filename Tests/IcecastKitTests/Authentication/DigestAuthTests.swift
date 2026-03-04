// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKit

// MARK: - DigestChallenge Parsing

@Suite("DigestAuthHandler — Challenge Parsing")
struct DigestAuthChallengeParsingTests {

    @Test("Valid Digest header parses correctly")
    func validDigestHeader() {
        let handler = DigestAuthHandler(
            username: "user", password: "pass"
        )
        let header =
            "Digest realm=\"icecast\", nonce=\"abc123\", qop=auth, opaque=\"xyz\""
        let challenge = handler.parseChallenge(header)

        #expect(challenge != nil)
        #expect(challenge?.realm == "icecast")
        #expect(challenge?.nonce == "abc123")
        #expect(challenge?.qop == "auth")
        #expect(challenge?.opaque == "xyz")
        #expect(challenge?.algorithm == .md5)
    }

    @Test("SHA-256 algorithm parsed correctly")
    func sha256Algorithm() {
        let handler = DigestAuthHandler(
            username: "user", password: "pass"
        )
        let header =
            "Digest realm=\"test\", nonce=\"n1\", algorithm=SHA-256"
        let challenge = handler.parseChallenge(header)

        #expect(challenge?.algorithm == .sha256)
    }

    @Test("Basic header returns nil")
    func basicHeaderReturnsNil() {
        let handler = DigestAuthHandler(
            username: "user", password: "pass"
        )
        let header = "Basic realm=\"icecast\""
        let challenge = handler.parseChallenge(header)

        #expect(challenge == nil)
    }

    @Test("Malformed header without realm returns nil")
    func malformedHeaderReturnsNil() {
        let handler = DigestAuthHandler(
            username: "user", password: "pass"
        )
        let header = "Digest nonce=\"abc\""
        let challenge = handler.parseChallenge(header)

        #expect(challenge == nil)
    }

    @Test("Empty header returns nil")
    func emptyHeaderReturnsNil() {
        let handler = DigestAuthHandler(
            username: "user", password: "pass"
        )
        let challenge = handler.parseChallenge("")

        #expect(challenge == nil)
    }

    @Test("Digest without qop parsed correctly")
    func digestWithoutQop() {
        let handler = DigestAuthHandler(
            username: "user", password: "pass"
        )
        let header = "Digest realm=\"test\", nonce=\"n1\""
        let challenge = handler.parseChallenge(header)

        #expect(challenge != nil)
        #expect(challenge?.qop == nil)
        #expect(challenge?.opaque == nil)
    }
}

// MARK: - Authorization Header Computation

@Suite("DigestAuthHandler — Authorization Header")
struct DigestAuthHeaderTests {

    @Test("MD5 without qop produces correct response")
    func md5WithoutQop() {
        let handler = DigestAuthHandler(
            username: "source", password: "hackme"
        )
        let challenge = DigestChallenge(
            realm: "icecast",
            nonce: "testnonce",
            algorithm: .md5,
            qop: nil,
            opaque: nil
        )

        let header = handler.authorizationHeader(
            for: challenge, method: "PUT", uri: "/live.mp3",
            cnonce: "clientnonce"
        )

        // Verify RFC 7616 calculation manually:
        // HA1 = MD5("source:icecast:hackme")
        let ha1 = AuthCrypto.md5("source:icecast:hackme")
        // HA2 = MD5("PUT:/live.mp3")
        let ha2 = AuthCrypto.md5("PUT:/live.mp3")
        // response = MD5(HA1:testnonce:HA2)
        let expectedResponse = AuthCrypto.md5("\(ha1):testnonce:\(ha2)")

        #expect(header.contains("response=\"\(expectedResponse)\""))
        #expect(header.hasPrefix("Digest "))
        #expect(header.contains("username=\"source\""))
        #expect(header.contains("realm=\"icecast\""))
        #expect(header.contains("nonce=\"testnonce\""))
        #expect(header.contains("uri=\"/live.mp3\""))
        #expect(!header.contains("qop="))
        #expect(!header.contains("nc="))
    }

    @Test("MD5 with qop=auth produces correct response")
    func md5WithQopAuth() {
        let handler = DigestAuthHandler(
            username: "source", password: "hackme"
        )
        let challenge = DigestChallenge(
            realm: "icecast",
            nonce: "testnonce",
            algorithm: .md5,
            qop: "auth",
            opaque: "opaquevalue"
        )

        let cnonce = "mycnonce"
        let header = handler.authorizationHeader(
            for: challenge, method: "PUT", uri: "/live.mp3",
            cnonce: cnonce
        )

        let ha1 = AuthCrypto.md5("source:icecast:hackme")
        let ha2 = AuthCrypto.md5("PUT:/live.mp3")
        let expectedResponse = AuthCrypto.md5(
            "\(ha1):testnonce:00000001:\(cnonce):auth:\(ha2)"
        )

        #expect(header.contains("response=\"\(expectedResponse)\""))
        #expect(header.contains("qop=auth"))
        #expect(header.contains("nc=00000001"))
        #expect(header.contains("cnonce=\"\(cnonce)\""))
        #expect(header.contains("opaque=\"opaquevalue\""))
    }

    @Test("SHA-256 algorithm produces correct response")
    func sha256Response() {
        let handler = DigestAuthHandler(
            username: "admin", password: "secret"
        )
        let challenge = DigestChallenge(
            realm: "test",
            nonce: "sha256nonce",
            algorithm: .sha256,
            qop: nil,
            opaque: nil
        )

        let header = handler.authorizationHeader(
            for: challenge, method: "GET", uri: "/stream",
            cnonce: "cn"
        )

        let ha1 = AuthCrypto.sha256("admin:test:secret")
        let ha2 = AuthCrypto.sha256("GET:/stream")
        let expectedResponse = AuthCrypto.sha256(
            "\(ha1):sha256nonce:\(ha2)"
        )

        #expect(header.contains("response=\"\(expectedResponse)\""))
        #expect(header.contains("algorithm=SHA-256"))
    }
}

// MARK: - BearerTokenAuth

@Suite("BearerTokenAuth")
struct BearerTokenAuthTests {

    @Test("authorizationHeaderValue returns Bearer token")
    func bearerHeaderValue() {
        let auth = BearerTokenAuth(token: "my-api-token-123")
        #expect(auth.authorizationHeaderValue == "Bearer my-api-token-123")
    }

    @Test("Empty token produces syntactically valid header")
    func emptyToken() {
        let auth = BearerTokenAuth(token: "")
        #expect(auth.authorizationHeaderValue == "Bearer ")
    }
}

// MARK: - QueryTokenAuth

@Suite("QueryTokenAuth")
struct QueryTokenAuthTests {

    @Test("Apply to mountpoint without query adds ?key=value")
    func applyWithoutExistingQuery() {
        let auth = QueryTokenAuth(key: "token", value: "secret123")
        let result = auth.apply(to: "/live.mp3")
        #expect(result == "/live.mp3?token=secret123")
    }

    @Test("Apply to mountpoint with existing query adds &key=value")
    func applyWithExistingQuery() {
        let auth = QueryTokenAuth(key: "token", value: "secret123")
        let result = auth.apply(to: "/live.mp3?format=mp3")
        #expect(result == "/live.mp3?format=mp3&token=secret123")
    }

    @Test("Special characters in value are percent-encoded")
    func specialCharactersEncoded() {
        let auth = QueryTokenAuth(key: "key", value: "hello world&foo=bar")
        let result = auth.apply(to: "/mount")
        #expect(result.contains("hello%20world"))
        #expect(result.contains("%26foo"))
        #expect(!result.contains("&foo=bar"))
    }
}
