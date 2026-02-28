// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import ArgumentParser
import IcecastKit

/// Streams audio data to an Icecast or SHOUTcast server.
struct StreamCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "stream",
        abstract: "Stream audio to an Icecast/SHOUTcast server"
    )

    @Option(name: .long, help: "Server hostname")
    var host: String = "localhost"

    @Option(name: .long, help: "Server port")
    var port: Int = 8000

    @Option(name: .long, help: "Mountpoint path")
    var mount: String = "/live.mp3"

    @Option(name: .long, help: "Audio file to stream")
    var file: String = ""

    func run() async throws {
        print("Streaming is not yet implemented. Coming in a future release.")
    }
}
