// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKitCommands

@Suite("IcecastKit CLI Commands")
struct IcecastKitCommandTests {

    @Test("Root command has correct command name")
    func rootCommandName() {
        #expect(IcecastKitCommand.configuration.commandName == "icecast-cli")
    }

    @Test("Root command has correct version")
    func rootCommandVersion() {
        #expect(IcecastKitCommand.configuration.version == "0.1.0")
    }

    @Test("Root command has three subcommands")
    func rootCommandSubcommands() {
        #expect(IcecastKitCommand.configuration.subcommands.count == 3)
    }
}
