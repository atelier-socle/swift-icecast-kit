// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKitCommands

// MARK: - CLI Multi-Destination Parsing Tests

@Suite("CLI — Multi-Destination Parsing")
struct MultiDestinationCLITests {

    @Test("Parse dest with 5 components (no protocol)")
    func parseDestFiveComponents() throws {
        let parsed = try parseDestination(
            "primary:icecast.example.com:8000:/live.mp3:password1"
        )
        #expect(parsed.label == "primary")
        #expect(parsed.host == "icecast.example.com")
        #expect(parsed.port == 8000)
        #expect(parsed.mountpoint == "/live.mp3")
        #expect(parsed.password == "password1")
        #expect(parsed.protocolString == nil)
    }

    @Test("Parse dest with 6 components (with protocol)")
    func parseDestSixComponents() throws {
        let parsed = try parseDestination(
            "backup:radio.example.com:8001:/stream:secret:shoutcast"
        )
        #expect(parsed.label == "backup")
        #expect(parsed.host == "radio.example.com")
        #expect(parsed.port == 8001)
        #expect(parsed.mountpoint == "/stream")
        #expect(parsed.password == "secret")
        #expect(parsed.protocolString == "shoutcast")
    }

    @Test("Parse dest adds leading slash to mountpoint")
    func parseDestAddsSlash() throws {
        let parsed = try parseDestination(
            "test:host:8000:live.mp3:pass"
        )
        #expect(parsed.mountpoint == "/live.mp3")
    }

    @Test("Parse dest preserves existing leading slash")
    func parseDestPreservesSlash() throws {
        let parsed = try parseDestination(
            "test:host:8000:/live.mp3:pass"
        )
        #expect(parsed.mountpoint == "/live.mp3")
    }

    @Test("Parse dest throws on too few components")
    func parseDestTooFewComponents() {
        #expect(throws: CLIParseError.self) {
            try parseDestination("label:host:8000")
        }
    }

    @Test("Parse dest throws on invalid port")
    func parseDestInvalidPort() {
        #expect(throws: CLIParseError.self) {
            try parseDestination("label:host:notaport:/mount:pass")
        }
    }
}
