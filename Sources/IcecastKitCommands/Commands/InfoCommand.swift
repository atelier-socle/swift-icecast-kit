// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import ArgumentParser
import Foundation
import IcecastKit

/// Display server and mountpoint information via the Icecast admin API.
public struct InfoCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Display server/mountpoint information via admin API"
    )

    /// Server hostname.
    @Option(name: .long, help: "Server hostname")
    var host: String = "localhost"

    /// Server port.
    @Option(name: .long, help: "Server port")
    var port: Int = 8000

    /// Admin username.
    @Option(name: .long, help: "Admin username")
    var adminUser: String = "admin"

    /// Admin password.
    @Option(name: .long, help: "Admin password")
    var adminPass: String

    /// Specific mountpoint to query.
    @Option(name: .long, help: "Specific mountpoint to query (optional)")
    var mountpoint: String?

    /// Use TLS/HTTPS.
    @Flag(name: .long, help: "Use TLS/HTTPS")
    var tls: Bool = false

    /// Disable colored output.
    @Flag(name: .long, help: "Disable colored output")
    var noColor: Bool = false

    public init() {}

    public mutating func run() async throws {
        let color = ColorOutput(noColor: noColor)
        let credentials = IcecastCredentials(username: adminUser, password: adminPass)
        let adminClient = AdminMetadataClient(
            host: host, port: port, useTLS: tls, credentials: credentials
        )

        do {
            if let mountpoint {
                try await displayMountStats(adminClient: adminClient, mountpoint: mountpoint, color: color)
            } else {
                try await displayServerStats(adminClient: adminClient, color: color)
            }
        } catch let error as IcecastError {
            let progress = ProgressDisplay(color: color)
            print(progress.formatError("\(error)"))
            throw ExitCode(TestConnectionCommand.mapExitCode(error))
        }
    }

    private func displayMountStats(
        adminClient: AdminMetadataClient,
        mountpoint: String,
        color: ColorOutput
    ) async throws {
        let stats = try await adminClient.fetchMountStats(mountpoint: mountpoint)
        print(color.bold("Mountpoint: \(mountpoint)"))
        printMountInfo(stats, color: color)
    }

    private func displayServerStats(
        adminClient: AdminMetadataClient,
        color: ColorOutput
    ) async throws {
        let stats = try await adminClient.fetchServerStats()
        print(color.bold("Server Information"))
        print(OutputFormatter.formatField(key: "Version", value: stats.serverVersion.isEmpty ? "unknown" : stats.serverVersion))
        print(OutputFormatter.formatField(key: "Active mounts", value: "\(stats.activeMountpoints.count)"))
        print(OutputFormatter.formatField(key: "Total listeners", value: "\(stats.totalListeners)"))
        print(OutputFormatter.formatField(key: "Total sources", value: "\(stats.totalSources)"))
    }

    private func printMountInfo(_ stats: MountStats, color: ColorOutput) {
        print(OutputFormatter.formatField(key: "Listeners", value: "\(stats.listeners)"))
        if let title = stats.streamTitle {
            print(OutputFormatter.formatField(key: "Title", value: title))
        }
        if let bitrate = stats.bitrate {
            print(OutputFormatter.formatField(key: "Bitrate", value: "\(bitrate) kbps"))
        }
        if let genre = stats.genre {
            print(OutputFormatter.formatField(key: "Genre", value: genre))
        }
        if let contentType = stats.contentType {
            print(OutputFormatter.formatField(key: "Content-Type", value: contentType))
        }
    }
}
