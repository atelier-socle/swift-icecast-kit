// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import ArgumentParser
import Foundation
import IcecastKit

/// Measure available upload bandwidth to an Icecast server.
///
/// Connects to the server, sends test data at progressive bitrates,
/// and reports the measured bandwidth and recommended bitrate.
public struct ProbeCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "probe",
        abstract: "Measure upload bandwidth to an Icecast server"
    )

    // MARK: - Options

    /// Server hostname.
    @Option(name: .long, help: "Server hostname")
    var host: String = "localhost"

    /// Server port.
    @Option(name: .long, help: "Server port")
    var port: Int = 8000

    /// Mountpoint to use for the probe.
    @Option(name: .long, help: "Mountpoint for probe")
    var mountpoint: String = "/probe"

    /// Auth password.
    @Option(name: .long, help: "Source password")
    var password: String

    /// Probe duration in seconds.
    @Option(name: .long, help: "Probe duration in seconds (2–30)")
    var duration: Double = 5.0

    /// Audio content type.
    @Option(
        name: .long,
        help: "Audio type: mp3, aac, ogg-vorbis, ogg-opus (default: mp3)"
    )
    var contentType: String = "mp3"

    /// Auth username.
    @Option(name: .long, help: "Auth username")
    var username: String = "source"

    /// Disable colored output.
    @Flag(name: .long, help: "Disable colored output")
    var noColor: Bool = false

    public init() {}

    public mutating func run() async throws {
        let color = ColorOutput(noColor: noColor)

        guard duration >= 2.0, duration <= 30.0 else {
            print(
                color.error(
                    "Duration must be between 2 and 30 seconds, got \(duration)"
                ))
            throw ExitCode(ExitCodes.generalError)
        }

        let audioType = try parseContentType(contentType)
        let credentials = IcecastCredentials(
            username: username, password: password
        )

        print(
            color.info(
                "Probing \(host):\(port)\(mountpoint) for \(duration)s..."
            ))

        let probe = IcecastBandwidthProbe()
        let result: IcecastProbeResult

        do {
            result = try await probe.measure(
                host: host,
                port: port,
                mountpoint: mountpoint,
                credentials: credentials,
                contentType: audioType,
                duration: duration
            )
        } catch let error as IcecastError {
            print(color.error("\(error)"))
            throw ExitCode(TestConnectionCommand.mapExitCode(error))
        }

        printResult(result, color: color)
    }

    private func printResult(
        _ result: IcecastProbeResult, color: ColorOutput
    ) {
        let bwMbps = result.uploadBandwidth / 1_000_000.0
        let bitrateKbps = result.recommendedBitrate / 1000

        print(color.success("Probe complete."))
        print("  Upload bandwidth: \(String(format: "%.1f", bwMbps)) Mbps")
        print(
            "  Write latency:    \(String(format: "%.0f", result.averageWriteLatency)) ms avg, \(String(format: "%.0f", result.writeLatencyVariance)) ms variance"
        )
        print(
            "  Stability score:  \(String(format: "%.0f", result.stabilityScore))/100"
        )
        print("  Latency class:    \(result.latencyClass.rawValue)")
        print(
            "  Recommended \(contentType.uppercased()) bitrate: \(bitrateKbps) kbps"
        )
        if let version = result.serverVersion {
            print("  Server version:   \(version)")
        }
    }
}
