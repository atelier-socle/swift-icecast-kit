// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import ArgumentParser
import IcecastKit

/// Tests connectivity to a streaming server.
struct TestConnectionCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "test-connection",
        abstract: "Test connectivity to a streaming server"
    )

    @Option(name: .long, help: "Server hostname")
    var host: String = "localhost"

    @Option(name: .long, help: "Server port")
    var port: Int = 8000

    func run() async throws {
        print("Connection testing is not yet implemented. Coming in a future release.")
    }
}
