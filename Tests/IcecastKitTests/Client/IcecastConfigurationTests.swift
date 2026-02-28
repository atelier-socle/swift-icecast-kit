// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("IcecastConfiguration")
struct IcecastConfigurationTests {

    // MARK: - Initialization Defaults

    @Test("Default port is 8000")
    func defaultPort() {
        let config = IcecastConfiguration(host: "localhost", mountpoint: "/live.mp3")
        #expect(config.port == 8000)
    }

    @Test("Default useTLS is false")
    func defaultUseTLS() {
        let config = IcecastConfiguration(host: "localhost", mountpoint: "/live.mp3")
        #expect(!config.useTLS)
    }

    @Test("Default contentType is mp3")
    func defaultContentType() {
        let config = IcecastConfiguration(host: "localhost", mountpoint: "/live.mp3")
        #expect(config.contentType == .mp3)
    }

    @Test("Default protocolMode is auto")
    func defaultProtocolMode() {
        let config = IcecastConfiguration(host: "localhost", mountpoint: "/live.mp3")
        #expect(config.protocolMode == .auto)
    }

    @Test("Default metadataInterval is 8192")
    func defaultMetadataInterval() {
        let config = IcecastConfiguration(host: "localhost", mountpoint: "/live.mp3")
        #expect(config.metadataInterval == 8192)
    }

    @Test("Default adminCredentials is nil")
    func defaultAdminCredentials() {
        let config = IcecastConfiguration(host: "localhost", mountpoint: "/live.mp3")
        #expect(config.adminCredentials == nil)
    }

    @Test("Custom values are stored correctly")
    func customValues() {
        let station = StationInfo(name: "Test Radio")
        let admin = IcecastCredentials(username: "admin", password: "secret")
        let config = IcecastConfiguration(
            host: "radio.example.com",
            port: 9000,
            mountpoint: "/stream.aac",
            useTLS: true,
            contentType: .aac,
            stationInfo: station,
            protocolMode: .icecastPUT,
            adminCredentials: admin,
            metadataInterval: 4096
        )
        #expect(config.host == "radio.example.com")
        #expect(config.port == 9000)
        #expect(config.mountpoint == "/stream.aac")
        #expect(config.useTLS)
        #expect(config.contentType == .aac)
        #expect(config.stationInfo.name == "Test Radio")
        #expect(config.protocolMode == .icecastPUT)
        #expect(config.adminCredentials == admin)
        #expect(config.metadataInterval == 4096)
    }

    // MARK: - Codable

    @Test("Codable roundtrip preserves all values")
    func codableRoundtrip() throws {
        let config = IcecastConfiguration(
            host: "radio.example.com",
            port: 9000,
            mountpoint: "/live.ogg",
            useTLS: true,
            contentType: .oggVorbis,
            protocolMode: .shoutcastV2(streamId: 3),
            metadataInterval: 4096
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(IcecastConfiguration.self, from: data)
        #expect(decoded == config)
    }

    // MARK: - Hashable

    @Test("Equal configurations hash equally")
    func hashable() {
        let c1 = IcecastConfiguration(host: "a", mountpoint: "/b")
        let c2 = IcecastConfiguration(host: "a", mountpoint: "/b")
        #expect(c1 == c2)
        #expect(c1.hashValue == c2.hashValue)
    }

    @Test("Different configurations are not equal")
    func notEqual() {
        let c1 = IcecastConfiguration(host: "a", mountpoint: "/b")
        let c2 = IcecastConfiguration(host: "a", port: 9000, mountpoint: "/b")
        #expect(c1 != c2)
    }

    // MARK: - URL Parsing (icecast://)

    @Test("Parses icecast:// URL with all components")
    func parseIcecastFull() throws {
        let (config, creds) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@radio.example.com:8000/live.mp3"
        )
        #expect(config.host == "radio.example.com")
        #expect(config.port == 8000)
        #expect(config.mountpoint == "/live.mp3")
        #expect(config.contentType == .mp3)
        #expect(config.protocolMode == .auto)
        #expect(!config.useTLS)
        #expect(creds.username == "source")
        #expect(creds.password == "hackme")
    }

    @Test("Parses icecast:// URL missing port defaults to 8000")
    func parseIcecastMissingPort() throws {
        let (config, _) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@radio.example.com/live.mp3"
        )
        #expect(config.port == 8000)
    }

    @Test("Parses icecast:// URL missing mountpoint defaults to /stream")
    func parseIcecastMissingMountpoint() throws {
        let (config, _) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@radio.example.com:8000"
        )
        #expect(config.mountpoint == "/stream")
    }

    @Test("Parses icecast:// URL missing username defaults to source")
    func parseIcecastMissingUsername() throws {
        let (_, creds) = try IcecastConfiguration.from(
            url: "icecast://:hackme@radio.example.com:8000/live.mp3"
        )
        #expect(creds.username == "source")
    }

    @Test("Parses icecast:// URL missing password throws credentialsRequired")
    func parseIcecastMissingPassword() {
        #expect(throws: IcecastError.credentialsRequired) {
            try IcecastConfiguration.from(url: "icecast://source@radio.example.com:8000/live.mp3")
        }
    }

    // MARK: - URL Parsing (shoutcast://)

    @Test("Parses shoutcast:// URL as shoutcastV1 mode")
    func parseShoutcastV1() throws {
        let (config, creds) = try IcecastConfiguration.from(
            url: "shoutcast://hackme@radio.example.com:8000/"
        )
        #expect(config.protocolMode == .shoutcastV1)
        #expect(creds.password == "hackme")
    }

    @Test("Parses shoutcast:// URL with streamId as shoutcastV2 mode")
    func parseShoutcastV2() throws {
        let (config, _) = try IcecastConfiguration.from(
            url: "shoutcast://hackme@radio.example.com:8000/?streamId=2"
        )
        #expect(config.protocolMode == .shoutcastV2(streamId: 2))
    }

    @Test("SHOUTcast v2 credentials have correct stream ID encoding")
    func shoutcastV2Credentials() throws {
        let (_, creds) = try IcecastConfiguration.from(
            url: "shoutcast://hackme@radio.example.com:8000/?streamId=2"
        )
        #expect(creds.username == "sid=2")
        #expect(creds.password == "hackme")
    }

    // MARK: - URL Parsing (http:// / https://)

    @Test("Parses http:// URL same as icecast://")
    func parseHTTP() throws {
        let (config, creds) = try IcecastConfiguration.from(
            url: "http://source:hackme@radio.example.com:8000/live.mp3"
        )
        #expect(config.host == "radio.example.com")
        #expect(config.protocolMode == .auto)
        #expect(!config.useTLS)
        #expect(creds.username == "source")
        #expect(creds.password == "hackme")
    }

    @Test("Parses https:// URL with useTLS true")
    func parseHTTPS() throws {
        let (config, _) = try IcecastConfiguration.from(
            url: "https://source:hackme@radio.example.com:8000/live.mp3"
        )
        #expect(config.useTLS)
    }

    // MARK: - URL Parsing (content type detection)

    @Test("Detects mp3 content type from mountpoint")
    func detectMP3FromURL() throws {
        let (config, _) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@host:8000/live.mp3"
        )
        #expect(config.contentType == .mp3)
    }

    @Test("Detects aac content type from mountpoint")
    func detectAACFromURL() throws {
        let (config, _) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@host:8000/stream.aac"
        )
        #expect(config.contentType == .aac)
    }

    @Test("Detects ogg content type from mountpoint")
    func detectOggFromURL() throws {
        let (config, _) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@host:8000/radio.ogg"
        )
        #expect(config.contentType == .oggVorbis)
    }

    @Test("Detects opus content type from mountpoint")
    func detectOpusFromURL() throws {
        let (config, _) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@host:8000/radio.opus"
        )
        #expect(config.contentType == .oggOpus)
    }

    @Test("No extension defaults to mp3 content type")
    func noExtensionDefaultsToMP3() throws {
        let (config, _) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@host:8000/stream"
        )
        #expect(config.contentType == .mp3)
    }

    // MARK: - URL Parsing (errors)

    @Test("Invalid URL string throws invalidMountpoint")
    func parseInvalidURL() {
        #expect(throws: IcecastError.self) {
            try IcecastConfiguration.from(url: "not a url at all %%")
        }
    }

    @Test("Missing scheme throws invalidMountpoint")
    func parseMissingScheme() {
        #expect(throws: IcecastError.self) {
            try IcecastConfiguration.from(url: "radio.example.com:8000/live.mp3")
        }
    }

    @Test("Unsupported scheme throws invalidMountpoint")
    func parseUnsupportedScheme() {
        #expect(throws: IcecastError.self) {
            try IcecastConfiguration.from(url: "ftp://source:hackme@host:8000/live.mp3")
        }
    }

    @Test("Missing host throws invalidMountpoint")
    func parseMissingHost() {
        #expect(throws: IcecastError.self) {
            try IcecastConfiguration.from(url: "icecast://source:hackme@:8000/live.mp3")
        }
    }

    @Test("SHOUTcast URL with no credentials throws credentialsRequired")
    func parseShoutcastNoCredentials() {
        #expect(throws: IcecastError.credentialsRequired) {
            try IcecastConfiguration.from(url: "shoutcast://radio.example.com:8000/")
        }
    }

    // MARK: - URL Parsing (edge cases)

    @Test("Port extraction from URL")
    func portExtraction() throws {
        let (config, _) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@host:9000/live.mp3"
        )
        #expect(config.port == 9000)
    }

    @Test("Special characters in password (URL-encoded)")
    func specialCharsInPassword() throws {
        let (_, creds) = try IcecastConfiguration.from(
            url: "icecast://source:p%40ss%2Fw0rd@host:8000/live.mp3"
        )
        #expect(creds.password == "p@ss/w0rd")
    }

    @Test("Unicode in mountpoint path")
    func unicodeMountpoint() throws {
        let (config, _) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@host:8000/radio%20fran%C3%A7aise.mp3"
        )
        #expect(config.mountpoint.contains("française"))
    }
}
