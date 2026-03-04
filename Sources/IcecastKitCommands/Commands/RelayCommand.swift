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

        // Set up recorder if --record is specified
        var recorder: StreamRecorder?
        if let recordDir = record {
            let contentType = await relay.detectedContentType ?? .mp3
            let config = RecordingConfiguration(
                directory: recordDir, contentType: contentType
            )
            let rec = StreamRecorder(configuration: config)
            try await rec.start()
            recorder = rec
            print(color.info("Recording to \(recordDir)"))
        }

        // relayLoop guarantees recorder.stop() in all exit paths
        await relayLoop(
            relay: relay, clients: clients, recorder: recorder
        )

        for client in clients {
            await client.disconnect()
        }
        await relay.disconnect()

        let received = await relay.bytesReceived
        print(color.success("Relay stopped."))
        print("  Bytes received: \(received)")
        if let rec = recorder {
            let stats = await rec.statistics
            print(
                "  Recorded: \(stats.bytesWritten) bytes, "
                    + "\(stats.filesCreated) file(s)"
            )
        }
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
        relay: IcecastRelay,
        clients: [IcecastClient],
        recorder: StreamRecorder?
    ) async {
        let startTime = Date()
        for await chunk in relay.audioStream {
            for client in clients {
                try? await client.send(chunk.data)
            }
            try? await recorder?.write(chunk.data)
            if let seconds = duration {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= seconds { break }
            }
        }
        // Stop recorder in all exit paths: stream ended, duration elapsed
        if let rec = recorder {
            _ = try? await rec.stop()
        }
    }
}
