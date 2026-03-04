// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKitCommands

// MARK: - CLI Relay Command Tests

@Suite("CLI — Relay Command")
struct RelayCommandTests {

    @Test("relay command name and abstract")
    func relayCommandConfig() {
        #expect(RelayCommand.configuration.commandName == "relay")
        #expect(
            RelayCommand.configuration.abstract
                == "Relay an Icecast stream (receive, re-publish, record)"
        )
    }

    @Test("relay requires --source")
    func relayRequiresSource() {
        #expect(throws: Error.self) {
            try RelayCommand.parse([])
        }
    }

    @Test("--source alone without --dest or --record is valid parse")
    func sourceAlone() throws {
        let command = try RelayCommand.parse([
            "--source", "http://radio.example.com:8000/live.mp3"
        ])
        #expect(
            command.source == "http://radio.example.com:8000/live.mp3"
        )
        #expect(command.dest.isEmpty)
        #expect(command.record == nil)
    }

    @Test("--source + --record parses correctly")
    func sourceAndRecord() throws {
        let command = try RelayCommand.parse([
            "--source", "http://radio.example.com:8000/live.mp3",
            "--record", "/tmp/output"
        ])
        #expect(command.record == "/tmp/output")
    }

    @Test("--source + --dest parses correctly")
    func sourceAndDest() throws {
        let command = try RelayCommand.parse([
            "--source", "http://radio.example.com:8000/live.mp3",
            "--dest", "primary:icecast.local:8000:/relay.mp3:password"
        ])
        #expect(command.dest.count == 1)
        #expect(command.dest[0] == "primary:icecast.local:8000:/relay.mp3:password")
    }

    @Test("--source + --dest + --record parses correctly")
    func sourceDestAndRecord() throws {
        let command = try RelayCommand.parse([
            "--source", "http://radio.example.com:8000/live.mp3",
            "--dest", "primary:icecast.local:8000:/relay.mp3:password",
            "--record", "/tmp/output"
        ])
        #expect(command.dest.count == 1)
        #expect(command.record == "/tmp/output")
    }

    @Test("multiple --dest parses correctly")
    func multipleDest() throws {
        let command = try RelayCommand.parse([
            "--source", "http://radio.example.com:8000/live.mp3",
            "--dest", "primary:host1:8000:/relay1.mp3:pass1",
            "--dest", "backup:host2:8000:/relay2.mp3:pass2"
        ])
        #expect(command.dest.count == 2)
    }

    @Test("--duration parses correctly")
    func durationOption() throws {
        let command = try RelayCommand.parse([
            "--source", "http://radio.example.com:8000/live.mp3",
            "--record", "/tmp/output",
            "--duration", "60"
        ])
        #expect(command.duration == 60.0)
    }

    @Test("--no-color flag parses correctly")
    func noColorFlag() throws {
        let command = try RelayCommand.parse([
            "--source", "http://radio.example.com:8000/live.mp3",
            "--record", "/tmp/output",
            "--no-color"
        ])
        #expect(command.noColor)
    }

    @Test("default duration is nil")
    func defaultDuration() throws {
        let command = try RelayCommand.parse([
            "--source", "http://radio.example.com:8000/live.mp3",
            "--record", "/tmp/output"
        ])
        #expect(command.duration == nil)
    }
}
