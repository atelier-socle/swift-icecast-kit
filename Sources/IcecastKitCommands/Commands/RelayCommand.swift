// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import ArgumentParser
import Foundation
import IcecastKit

/// Relay an Icecast stream: receive audio from a source and optionally
/// re-publish to other servers and/or record locally.
public struct RelayCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "relay",
        abstract: "Relay an Icecast stream (receive, re-publish, record)"
    )

    // MARK: - Options

    /// Source stream URL.
    @Option(name: .long, help: "URL of the source Icecast stream to relay")
    var source: String

    /// Re-publish destinations (label:host:port:mountpoint:password).
    @Option(
        name: .long,
        help: "Re-publish destination (label:host:port:mountpoint:password)"
    )
    var dest: [String] = []

    /// Record the relayed stream to this directory.
    @Option(name: .long, help: "Record the relayed stream to this directory")
    var record: String?

    /// Stop after N seconds.
    @Option(name: .long, help: "Stop after N seconds (default: infinite)")
    var duration: Double?

    /// Disable colored output.
    @Flag(name: .long, help: "Disable colored output")
    var noColor: Bool = false

    public init() {}

    public mutating func run() async throws {
        let color = ColorOutput(noColor: noColor)

        guard !dest.isEmpty || record != nil else {
            print(
                color.error("At least one --dest or --record is required")
            )
            throw ExitCode(ExitCodes.argumentError)
        }

        let relay = try await connectRelay(color: color)
        let clients = await connectDestinations(color: color)

        if let recordDir = record {
            print(color.info("Recording to \(recordDir)"))
        }

        await relayLoop(relay: relay, clients: clients)

        for client in clients {
            await client.disconnect()
        }
        await relay.disconnect()

        let received = await relay.bytesReceived
        print(color.success("Relay stopped."))
        print("  Bytes received: \(received)")
    }

    // MARK: - Helpers

    private func connectRelay(color: ColorOutput) async throws -> IcecastRelay {
        let config = IcecastRelayConfiguration(sourceURL: source)
        print(color.info("Connecting to \(source)..."))
        let relay = IcecastRelay(configuration: config)
        do {
            try await relay.connect()
        } catch let error as IcecastError {
            print(color.error("\(error)"))
            throw ExitCode(TestConnectionCommand.mapExitCode(error))
        }
        let serverInfo = await relay.serverVersion ?? "unknown"
        print(color.success("Connected to \(serverInfo)"))
        return relay
    }

    private func connectDestinations(
        color: ColorOutput
    ) async -> [IcecastClient] {
        var clients: [IcecastClient] = []
        for destString in dest {
            guard let parsed = try? parseDestination(destString) else {
                continue
            }
            let config = IcecastConfiguration(
                host: parsed.host,
                port: parsed.port,
                mountpoint: parsed.mountpoint
            )
            let creds = IcecastCredentials(password: parsed.password)
            let client = IcecastClient(
                configuration: config, credentials: creds
            )
            do {
                try await client.connect()
                clients.append(client)
                print(
                    color.info(
                        "Re-publishing to \(parsed.label)"
                    )
                )
            } catch {
                print(
                    color.warning(
                        "Failed to connect to \(parsed.label): \(error)"
                    )
                )
            }
        }
        return clients
    }

    private func relayLoop(
        relay: IcecastRelay, clients: [IcecastClient]
    ) async {
        let startTime = Date()
        for await chunk in relay.audioStream {
            for client in clients {
                try? await client.send(chunk.data)
            }
            if let seconds = duration {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= seconds { break }
            }
        }
    }
}
