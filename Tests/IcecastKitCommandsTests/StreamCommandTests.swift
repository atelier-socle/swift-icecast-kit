// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKit
@testable import IcecastKitCommands

@Suite("StreamCommand")
struct StreamCommandTests {

    // MARK: - Default Values

    @Test("Default host is localhost")
    func defaultHost() throws {
        let cmd = try StreamCommand.parse(["test.mp3", "--password", "secret"])
        #expect(cmd.host == "localhost")
    }

    @Test("Default port is 8000")
    func defaultPort() throws {
        let cmd = try StreamCommand.parse(["test.mp3", "--password", "secret"])
        #expect(cmd.port == 8000)
    }

    @Test("Default mountpoint is /stream")
    func defaultMountpoint() throws {
        let cmd = try StreamCommand.parse(["test.mp3", "--password", "secret"])
        #expect(cmd.mountpoint == "/stream")
    }

    @Test("Default username is source")
    func defaultUsername() throws {
        let cmd = try StreamCommand.parse(["test.mp3", "--password", "secret"])
        #expect(cmd.username == "source")
    }

    @Test("Default protocol is auto")
    func defaultProtocol() throws {
        let cmd = try StreamCommand.parse(["test.mp3", "--password", "secret"])
        #expect(cmd.protocol == "auto")
    }

    // MARK: - Protocol Parsing

    @Test("Parse protocol auto")
    func parseProtocolAuto() throws {
        let mode = try parseProtocolMode("auto")
        #expect(mode == .auto)
    }

    @Test("Parse protocol icecast-put")
    func parseProtocolIcecastPut() throws {
        let mode = try parseProtocolMode("icecast-put")
        #expect(mode == .icecastPUT)
    }

    @Test("Parse protocol icecast-source")
    func parseProtocolIcecastSource() throws {
        let mode = try parseProtocolMode("icecast-source")
        #expect(mode == .icecastSOURCE)
    }

    @Test("Parse protocol shoutcast-v1")
    func parseProtocolShoutcastV1() throws {
        let mode = try parseProtocolMode("shoutcast-v1")
        #expect(mode == .shoutcastV1)
    }

    @Test("Parse protocol shoutcast-v2 with stream id")
    func parseProtocolShoutcastV2() throws {
        let mode = try parseProtocolMode("shoutcast-v2:3")
        #expect(mode == .shoutcastV2(streamId: 3))
    }

    @Test("Invalid protocol string throws error")
    func invalidProtocolThrows() {
        #expect(throws: CLIParseError.self) {
            _ = try parseProtocolMode("invalid")
        }
    }

    // MARK: - Content Type Parsing

    @Test("Parse content type mp3")
    func parseContentTypeMp3() throws {
        let type = try parseContentType("mp3")
        #expect(type == .mp3)
    }

    @Test("Parse content type aac")
    func parseContentTypeAac() throws {
        let type = try parseContentType("aac")
        #expect(type == .aac)
    }

    @Test("Parse content type ogg-vorbis")
    func parseContentTypeOggVorbis() throws {
        let type = try parseContentType("ogg-vorbis")
        #expect(type == .oggVorbis)
    }

    @Test("Parse content type ogg-opus")
    func parseContentTypeOggOpus() throws {
        let type = try parseContentType("ogg-opus")
        #expect(type == .oggOpus)
    }

    @Test("Invalid content type string throws error")
    func invalidContentTypeThrows() {
        #expect(throws: CLIParseError.self) {
            _ = try parseContentType("wav")
        }
    }

    @Test("Content type auto-detect from file extension")
    func contentTypeAutoDetect() {
        #expect(AudioFileReader.detectContentType(from: "song.mp3") == .mp3)
        #expect(AudioFileReader.detectContentType(from: "song.aac") == .aac)
        #expect(AudioFileReader.detectContentType(from: "song.ogg") == .oggVorbis)
        #expect(AudioFileReader.detectContentType(from: "song.opus") == .oggOpus)
    }

    // MARK: - Flag Parsing

    @Test("loop flag parsing")
    func loopFlagParsing() throws {
        let cmd = try StreamCommand.parse(["test.mp3", "--password", "secret", "--loop"])
        #expect(cmd.loop)
    }

    @Test("no-reconnect flag parsing")
    func noReconnectFlagParsing() throws {
        let cmd = try StreamCommand.parse(["test.mp3", "--password", "secret", "--no-reconnect"])
        #expect(cmd.noReconnect)
    }

    @Test("tls flag parsing")
    func tlsFlagParsing() throws {
        let cmd = try StreamCommand.parse(["test.mp3", "--password", "secret", "--tls"])
        #expect(cmd.tls)
    }

    @Test("bitrate option parsing")
    func bitrateParsing() throws {
        let cmd = try StreamCommand.parse(["test.mp3", "--password", "secret", "--bitrate", "320"])
        #expect(cmd.bitrate == 320)
    }

    @Test("title option parsing")
    func titleParsing() throws {
        let cmd = try StreamCommand.parse(["test.mp3", "--password", "secret", "--title", "My Song"])
        #expect(cmd.title == "My Song")
    }

    @Test("Missing password parses but password is nil")
    func missingPasswordParsesNil() throws {
        let cmd = try StreamCommand.parse(["test.mp3"])
        #expect(cmd.password == nil)
    }

    @Test("Missing file argument fails validation")
    func missingFileFails() {
        #expect(throws: Error.self) {
            _ = try StreamCommand.parse(["--password", "secret"])
        }
    }

    // MARK: - Auth Type Parsing

    @Test("Default auth-type is basic")
    func defaultAuthType() throws {
        let cmd = try StreamCommand.parse(["test.mp3", "--password", "secret"])
        #expect(cmd.authType == "basic")
    }

    @Test("Auth-type digest parsing")
    func authTypeDigest() throws {
        let cmd = try StreamCommand.parse([
            "test.mp3", "--password", "secret", "--auth-type", "digest"
        ])
        #expect(cmd.authType == "digest")
    }

    @Test("Auth-type bearer with token parsing")
    func authTypeBearerWithToken() throws {
        let cmd = try StreamCommand.parse([
            "test.mp3", "--auth-type", "bearer", "--token", "my-token"
        ])
        #expect(cmd.authType == "bearer")
        #expect(cmd.token == "my-token")
    }

    @Test("resolveAuthentication basic returns .basic")
    func resolveBasicAuth() throws {
        let auth = try resolveAuthentication(
            authType: "basic", username: "source",
            password: "hackme", token: nil
        )
        if case .basic(let user, let pass) = auth {
            #expect(user == "source")
            #expect(pass == "hackme")
        } else {
            Issue.record("Expected .basic authentication")
        }
    }

    @Test("resolveAuthentication digest returns .digest")
    func resolveDigestAuth() throws {
        let auth = try resolveAuthentication(
            authType: "digest", username: "admin",
            password: "secret", token: nil
        )
        if case .digest(let user, let pass) = auth {
            #expect(user == "admin")
            #expect(pass == "secret")
        } else {
            Issue.record("Expected .digest authentication")
        }
    }

    @Test("resolveAuthentication bearer returns .bearer")
    func resolveBearerAuth() throws {
        let auth = try resolveAuthentication(
            authType: "bearer", username: "source",
            password: nil, token: "my-api-token"
        )
        if case .bearer(let tok) = auth {
            #expect(tok == "my-api-token")
        } else {
            Issue.record("Expected .bearer authentication")
        }
    }

    @Test("resolveAuthentication query-token returns .queryToken")
    func resolveQueryTokenAuth() throws {
        let auth = try resolveAuthentication(
            authType: "query-token", username: "source",
            password: nil, token: "abc123"
        )
        if case .queryToken(let key, let value) = auth {
            #expect(key == "token")
            #expect(value == "abc123")
        } else {
            Issue.record("Expected .queryToken authentication")
        }
    }

    @Test("resolveAuthentication bearer without token throws")
    func resolveBearerWithoutTokenThrows() {
        #expect(throws: CLIParseError.self) {
            _ = try resolveAuthentication(
                authType: "bearer", username: "source",
                password: nil, token: nil
            )
        }
    }

    @Test("resolveAuthentication invalid type throws")
    func resolveInvalidAuthTypeThrows() {
        #expect(throws: CLIParseError.self) {
            _ = try resolveAuthentication(
                authType: "oauth2", username: "source",
                password: "pass", token: nil
            )
        }
    }
}
