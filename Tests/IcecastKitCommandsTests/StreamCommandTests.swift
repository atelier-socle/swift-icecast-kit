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

    @Test("Missing password fails validation")
    func missingPasswordFails() {
        #expect(throws: Error.self) {
            _ = try StreamCommand.parse(["test.mp3"])
        }
    }

    @Test("Missing file argument fails validation")
    func missingFileFails() {
        #expect(throws: Error.self) {
            _ = try StreamCommand.parse(["--password", "secret"])
        }
    }
}
