// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Showcase — Authentication")
struct AuthenticationShowcaseTests {

    // MARK: - Showcase 1: Basic auth header

    @Test("Basic auth produces correct Authorization header")
    func basicAuthProducesCorrectHeader() {
        let auth = IcecastAuthentication.basic(username: "source", password: "hackme")
        let header = auth.initialAuthorizationHeader()
        #expect(header != nil)
        #expect(header?.hasPrefix("Basic ") == true)
    }

    // MARK: - Showcase 2: Bearer auth header

    @Test("Bearer auth produces correct Authorization header")
    func bearerAuthProducesCorrectHeader() {
        let auth = IcecastAuthentication.bearer(token: "my-api-token-12345")
        let header = auth.initialAuthorizationHeader()
        #expect(header == "Bearer my-api-token-12345")
    }

    // MARK: - Showcase 3: QueryToken modifies mountpoint

    @Test("QueryToken modifies mountpoint with query parameter")
    func queryTokenModifiesMountpoint() {
        let qt = QueryTokenAuth(key: "token", value: "abc123")
        let modified = qt.apply(to: "/live.mp3")
        #expect(modified == "/live.mp3?token=abc123")

        // Existing query string appends with &
        let existing = qt.apply(to: "/live.mp3?format=mp3")
        #expect(existing == "/live.mp3?format=mp3&token=abc123")
    }

    // MARK: - Showcase 4: QueryToken percent-encodes special characters

    @Test("QueryToken percent-encodes special characters in value")
    func queryTokenPercentEncodesSpecialChars() {
        let qt = QueryTokenAuth(key: "token", value: "a=b&c+d")
        let modified = qt.apply(to: "/stream")
        #expect(!modified.contains("=b"))
        #expect(modified.hasPrefix("/stream?token="))
    }

    // MARK: - Showcase 5: Digest RFC 7616 challenge parsing

    @Test("Digest auth handler parses RFC 7616 challenge correctly")
    func digestResponseConformsToRFC7616() {
        let handler = DigestAuthHandler(username: "source", password: "hackme")
        let challenge = handler.parseChallenge(
            "Digest realm=\"icecast\", nonce=\"abc123\", algorithm=MD5, qop=auth"
        )
        #expect(challenge != nil)
        #expect(challenge?.realm == "icecast")
        #expect(challenge?.nonce == "abc123")
        #expect(challenge?.algorithm == .md5)
        #expect(challenge?.qop == "auth")
    }

    // MARK: - Showcase 6: Digest with SHA-256

    @Test("Digest handler supports SHA-256 algorithm")
    func digestWithSHA256() {
        let handler = DigestAuthHandler(username: "source", password: "secret")
        let challenge = handler.parseChallenge(
            "Digest realm=\"radio\", nonce=\"xyz789\", algorithm=SHA-256"
        )
        #expect(challenge?.algorithm == .sha256)
    }

    // MARK: - Showcase 7: Digest authorization header generation

    @Test("Digest handler generates valid Authorization header")
    func digestWithQopIncludesNcAndCnonce() {
        let handler = DigestAuthHandler(username: "source", password: "hackme")
        let challenge = DigestChallenge(
            realm: "icecast",
            nonce: "abc123",
            algorithm: .md5,
            qop: "auth",
            opaque: nil
        )
        let header = handler.authorizationHeader(
            for: challenge, method: "SOURCE", uri: "/live.mp3"
        )
        #expect(header.contains("Digest "))
        #expect(header.contains("username=\"source\""))
        #expect(header.contains("realm=\"icecast\""))
        #expect(header.contains("nc="))
        #expect(header.contains("cnonce="))
        #expect(header.contains("response="))
    }

    // MARK: - Showcase 8: fromURL() parses embedded credentials

    @Test("Authentication parsed from URL with embedded credentials")
    func authenticationParsedFromURL() {
        let auth = IcecastAuthentication.fromURL(
            "http://admin:secret@radio.example.com:8000/live.mp3"
        )
        #expect(auth != nil)
        if case .basic(let user, let pass) = auth {
            #expect(user == "admin")
            #expect(pass == "secret")
        } else {
            Issue.record("Expected .basic authentication")
        }
    }

    // MARK: - Showcase 9: fromURL() returns nil without credentials

    @Test("fromURL returns nil for URL without credentials")
    func fromURLReturnsNilWithoutCredentials() {
        let auth = IcecastAuthentication.fromURL("http://radio.example.com:8000/live.mp3")
        #expect(auth == nil)
    }

    // MARK: - Showcase 10: stripCredentials()

    @Test("Credentials stripped from URL cleanly")
    func credentialsStrippedFromURL() {
        let clean = IcecastAuthentication.stripCredentials(
            from: "http://admin:secret@radio.example.com:8000/live.mp3"
        )
        #expect(!clean.contains("admin"))
        #expect(!clean.contains("secret"))
        #expect(clean.contains("radio.example.com"))
    }

    // MARK: - Showcase 11: stripCredentials() no-op for clean URL

    @Test("stripCredentials returns URL unchanged when no credentials")
    func stripCredentialsNoOp() {
        let url = "http://radio.example.com:8000/live.mp3"
        let clean = IcecastAuthentication.stripCredentials(from: url)
        #expect(clean == url)
    }

    // MARK: - Showcase 12: IcecastCredentials bridge

    @Test("IcecastCredentials.authentication bridge returns .basic")
    func credentialsBridgeToBasicAuthentication() {
        let creds = IcecastCredentials(username: "source", password: "hackme")
        let auth = creds.authentication
        if case .basic(let user, let pass) = auth {
            #expect(user == "source")
            #expect(pass == "hackme")
        } else {
            Issue.record("Expected .basic authentication")
        }
    }

    // MARK: - Showcase 13: AuthCrypto MD5

    @Test("AuthCrypto MD5 matches RFC 1321 test vector")
    func authCryptoMD5MatchesRFCVector() {
        let hash = AuthCrypto.md5("")
        #expect(hash == "d41d8cd98f00b204e9800998ecf8427e")

        let abc = AuthCrypto.md5("abc")
        #expect(abc == "900150983cd24fb0d6963f7d28e17f72")
    }

    // MARK: - Showcase 14: AuthCrypto SHA-256

    @Test("AuthCrypto SHA-256 matches FIPS 180-4 test vector")
    func authCryptoSHA256MatchesFIPSVector() {
        let hash = AuthCrypto.sha256("")
        #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

        let abc = AuthCrypto.sha256("abc")
        #expect(abc == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: - Showcase 15: Digest returns nil for non-Digest header

    @Test("Digest parseChallenge returns nil for Basic auth header")
    func digestReturnsNilForBasicHeader() {
        let handler = DigestAuthHandler(username: "source", password: "hackme")
        let result = handler.parseChallenge("Basic realm=\"icecast\"")
        #expect(result == nil)
    }

    // MARK: - Showcase 16: Bearer/queryToken credentials bridge is nil

    @Test("Bearer and queryToken have nil credentials bridge")
    func bearerAndQueryTokenCredentialsAreNil() {
        let bearer = IcecastAuthentication.bearer(token: "tok")
        #expect(bearer.credentials == nil)

        let qt = IcecastAuthentication.queryToken(key: "k", value: "v")
        #expect(qt.credentials == nil)
    }

    // MARK: - Showcase 17: Digest/shoutcast credentials bridge

    @Test("Digest and shoutcast authentication types bridge to credentials")
    func digestAndShoutcastCredentialsBridge() {
        let digest = IcecastAuthentication.digest(
            username: "admin", password: "secret"
        )
        #expect(digest.credentials?.username == "admin")
        #expect(digest.credentials?.password == "secret")

        let sc = IcecastAuthentication.shoutcast(password: "pass")
        #expect(sc.credentials != nil)

        let sc2 = IcecastAuthentication.shoutcastV2(password: "pass", streamId: 1)
        #expect(sc2.credentials != nil)
    }

    // MARK: - Showcase 18: Auth error descriptions

    @Test("Authentication error descriptions contain expected text")
    func authErrorDescriptionsContainExpectedText() {
        let digest = IcecastError.digestAuthFailed(reason: "bad nonce")
        #expect("\(digest)".contains("Digest"))

        let expired = IcecastError.tokenExpired
        #expect("\(expired)".contains("expired") || "\(expired)".contains("401"))

        let invalid = IcecastError.tokenInvalid
        #expect("\(invalid)".contains("invalid") || "\(invalid)".contains("403"))
    }

    // MARK: - Showcase 18b: Digest parseChallenge with unclosed quote

    @Test("Digest parseChallenge handles unclosed quoted value")
    func digestParseChallengeHandlesUnclosedQuote() {
        let handler = DigestAuthHandler(username: "source", password: "hackme")
        // The nonce value has an opening quote but no closing quote
        let challenge = handler.parseChallenge(
            "Digest realm=\"icecast\", nonce=\"abc123"
        )
        // Should still parse (takes rest of string as value)
        #expect(challenge != nil)
        #expect(challenge?.realm == "icecast")
        #expect(challenge?.nonce == "abc123")
    }

    // MARK: - Showcase 19: initialAuthorizationHeader nil for digest/query/shoutcast

    @Test("Digest, queryToken, and shoutcast return nil initial auth header")
    func noInitialHeaderForChallengeBasedAuth() {
        let digest = IcecastAuthentication.digest(
            username: "u", password: "p"
        )
        #expect(digest.initialAuthorizationHeader() == nil)

        let qt = IcecastAuthentication.queryToken(key: "k", value: "v")
        #expect(qt.initialAuthorizationHeader() == nil)

        let sc = IcecastAuthentication.shoutcast(password: "p")
        #expect(sc.initialAuthorizationHeader() == nil)

        let sc2 = IcecastAuthentication.shoutcastV2(password: "p", streamId: 1)
        #expect(sc2.initialAuthorizationHeader() == nil)
    }
}
