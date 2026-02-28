// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import ArgumentParser
import IcecastKit

/// Displays server and mountpoint information.
struct InfoCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Display server and mountpoint information"
    )

    @Option(name: .long, help: "Server hostname")
    var host: String = "localhost"

    @Option(name: .long, help: "Server port")
    var port: Int = 8000

    func run() async throws {
        print("Server info is not yet implemented. Coming in a future release.")
    }
}
