// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKitCommands

// MARK: - CLI Probe Command Tests

@Suite("CLI — Probe Command")
struct ProbeCommandTests {

    @Test("probe --help parses without error")
    func probeHelp() throws {
        // Verify the command can be constructed with defaults
        let command = ProbeCommand()
        #expect(ProbeCommand.configuration.commandName == "probe")
        #expect(
            ProbeCommand.configuration.abstract
                == "Measure upload bandwidth to an Icecast server"
        )
        _ = command
    }

    @Test("probe parses default options correctly")
    func probeDefaults() throws {
        let command = try ProbeCommand.parse([
            "--password", "secret"
        ])
        #expect(command.host == "localhost")
        #expect(command.port == 8000)
        #expect(command.mountpoint == "/probe")
        #expect(command.duration == 5.0)
        #expect(command.contentType == "mp3")
    }

    @Test("probe parses custom options")
    func probeCustomOptions() throws {
        let command = try ProbeCommand.parse([
            "--host", "radio.example.com",
            "--port", "9000",
            "--mountpoint", "/test",
            "--password", "mypass",
            "--duration", "10",
            "--content-type", "aac",
            "--username", "admin"
        ])
        #expect(command.host == "radio.example.com")
        #expect(command.port == 9000)
        #expect(command.mountpoint == "/test")
        #expect(command.password == "mypass")
        #expect(command.duration == 10.0)
        #expect(command.contentType == "aac")
        #expect(command.username == "admin")
    }

    @Test("probe requires --password")
    func probeRequiresPassword() {
        #expect(throws: Error.self) {
            try ProbeCommand.parse([])
        }
    }
}
