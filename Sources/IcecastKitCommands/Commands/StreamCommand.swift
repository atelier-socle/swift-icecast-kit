// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import ArgumentParser
import Foundation
import IcecastKit

/// Stream an audio file to an Icecast/SHOUTcast server.
///
/// Reads the audio file, connects to the server, and streams data
/// at approximately real-time pace based on bitrate.
/// Supports multi-destination streaming via `--dest`.
public struct StreamCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "stream",
        abstract: "Stream an audio file to an Icecast/SHOUTcast server"
    )

    // MARK: - Arguments

    /// Path to audio file (MP3, AAC, OGG).
    @Argument(help: "Path to audio file (MP3, AAC, OGG)")
    var file: String

    // MARK: - Connection Options

    /// Server hostname.
    @Option(name: .long, help: "Server hostname")
    var host: String = "localhost"

    /// Server port.
    @Option(name: .long, help: "Server port")
    var port: Int = 8000

    /// Mountpoint path.
    @Option(name: .long, help: "Mountpoint path")
    var mountpoint: String = "/stream"

    /// Auth username.
    @Option(name: .long, help: "Auth username")
    var username: String = "source"

    /// Auth password (required for single-destination mode).
    @Option(name: .long, help: "Auth password")
    var password: String?

    // MARK: - Multi-Destination Options

    /// Destination specifications for multi-destination streaming.
    @Option(
        name: .long,
        help: "Destination: label:host:port:mountpoint:password[:protocol]"
    )
    var dest: [String] = []

    // MARK: - Stream Options

    /// Audio type override.
    @Option(
        name: .long,
        help: "Audio type: mp3, aac, ogg-vorbis, ogg-opus (default: auto-detect)"
    )
    var contentType: String?

    /// Protocol mode.
    @Option(
        name: .long,
        help: "Protocol: auto, icecast-put, icecast-source, shoutcast-v1, shoutcast-v2:<id>"
    )
    var `protocol`: String = "auto"

    /// Initial stream title.
    @Option(name: .long, help: "Initial stream title")
    var title: String?

    /// Bitrate in kbps for pacing.
    @Option(
        name: .long,
        help: "Bitrate in kbps for pacing (auto-detected if possible)"
    )
    var bitrate: Int?

    // MARK: - Flags

    /// Loop the file continuously.
    @Flag(name: .long, help: "Loop the file continuously")
    var loop: Bool = false

    /// Disable auto-reconnect.
    @Flag(name: .long, help: "Disable auto-reconnect")
    var noReconnect: Bool = false

    /// Use TLS/HTTPS.
    @Flag(name: .long, help: "Use TLS/HTTPS")
    var tls: Bool = false

    /// Disable colored output.
    @Flag(name: .long, help: "Disable colored output")
    var noColor: Bool = false

    public init() {}

    public mutating func run() async throws {
        let color = ColorOutput(noColor: noColor)
        let progress = ProgressDisplay(color: color)

        var reader = try openAudioFile(color: color)

        if !dest.isEmpty {
            try await runMultiDestination(
                reader: &reader, progress: progress, color: color
            )
        } else {
            guard let password, !password.isEmpty else {
                throw CLIParseError.invalidDestination(
                    "Password is required for single-destination mode"
                )
            }
            try await runSingleDestination(
                password: password,
                reader: &reader,
                progress: progress,
                color: color
            )
        }
    }

    // MARK: - Single Destination

    private func runSingleDestination(
        password: String,
        reader: inout AudioFileReader,
        progress: ProgressDisplay,
        color: ColorOutput
    ) async throws {
        let config = try buildConfiguration(audioType: reader.contentType)
        let credentials = IcecastCredentials(
            username: username, password: password
        )
        let policy: ReconnectPolicy = noReconnect ? .none : .default
        let client = IcecastClient(
            configuration: config,
            credentials: credentials,
            reconnectPolicy: policy
        )
        try await connectAndStream(
            client: client, reader: &reader,
            progress: progress, color: color
        )
    }

    // MARK: - Multi-Destination

    private func runMultiDestination(
        reader: inout AudioFileReader,
        progress: ProgressDisplay,
        color: ColorOutput
    ) async throws {
        let multi = MultiIcecastClient()
        let policy: ReconnectPolicy = noReconnect ? .none : .default

        for destString in dest {
            let parsed = try parseDestination(destString)
            let mode: ProtocolMode
            if let protoStr = parsed.protocolString {
                mode =
                    protoStr == "shoutcast"
                    ? .shoutcastV1
                    : try parseProtocolMode(protoStr)
            } else {
                mode = .auto
            }
            let audioType: AudioContentType? = try contentType.map {
                try parseContentType($0)
            }
            let config = IcecastConfiguration(
                host: parsed.host,
                port: parsed.port,
                mountpoint: parsed.mountpoint,
                useTLS: tls,
                contentType: audioType ?? reader.contentType,
                protocolMode: mode,
                credentials: IcecastCredentials(password: parsed.password),
                reconnectPolicy: policy
            )
            try await multi.addDestination(
                parsed.label,
                configuration: config
            )
            print(
                color.info(
                    "  + \(parsed.label): \(parsed.host):\(parsed.port)\(parsed.mountpoint)"
                ))
        }

        try await multi.connectAll()
        let destCount = dest.count
        print(
            color.success(
                "Connected to \(destCount) destination\(destCount == 1 ? "" : "s")"
            ))

        if let title {
            await multi.updateMetadata(ICYMetadata(streamTitle: title))
        }

        let pacingBitrate = resolveBitrate(reader: reader)
        try await multiStreamLoop(
            multi: multi, reader: &reader,
            pacingBitrate: pacingBitrate, progress: progress
        )

        await multi.disconnectAll()
        let stats = await multi.statistics
        print(
            "\n"
                + color.success(
                    "✓ Stream complete. Sent \(ProgressDisplay.formatBytes(stats.aggregated.bytesSent))"
                ))
    }

    private func multiStreamLoop(
        multi: MultiIcecastClient,
        reader: inout AudioFileReader,
        pacingBitrate: Int,
        progress: ProgressDisplay
    ) async throws {
        let chunkSize = 4096
        let sleepPerChunk = Double(chunkSize) / (Double(pacingBitrate) / 8.0)
        let startTime = Date()

        while true {
            if let chunk = try reader.readChunk(size: chunkSize) {
                try await multi.send(chunk)
                let elapsed = Date().timeIntervalSince(startTime)
                let stats = await multi.statistics
                let line = progress.formatStreamingStatus(
                    elapsed: elapsed,
                    bytesSent: stats.aggregated.bytesSent,
                    bitrate: stats.aggregated.currentBitrate, title: title
                )
                print("\r\(line)", terminator: "")
                try await Task.sleep(
                    nanoseconds: UInt64(sleepPerChunk * 1_000_000_000)
                )
            } else if loop {
                try reader.reset()
            } else {
                break
            }
        }
    }

    // MARK: - Private Helpers

    private func openAudioFile(color: ColorOutput) throws -> AudioFileReader {
        let audioType: AudioContentType? = try contentType.map {
            try parseContentType($0)
        }
        let reader = try AudioFileReader(path: file, contentType: audioType)
        print(
            color.info(
                "📁 File: \(file) (\(ProgressDisplay.formatBytes(reader.fileSize)), \(reader.contentType.rawValue))"
            ))
        return reader
    }

    private func buildConfiguration(
        audioType: AudioContentType
    ) throws -> IcecastConfiguration {
        let mode = try parseProtocolMode(self.protocol)
        return IcecastConfiguration(
            host: host,
            port: port,
            mountpoint: mountpoint,
            useTLS: tls,
            contentType: audioType,
            protocolMode: mode
        )
    }

    private func connectAndStream(
        client: IcecastClient,
        reader: inout AudioFileReader,
        progress: ProgressDisplay,
        color: ColorOutput
    ) async throws {
        try await client.connect()
        print(
            progress.formatConnected(
                host: host, port: port,
                mountpoint: mountpoint, protocolName: self.protocol
            ))

        if let title {
            try await client.updateMetadata(ICYMetadata(streamTitle: title))
        }

        let pacingBitrate = resolveBitrate(reader: reader)
        try await streamLoop(
            client: client, reader: &reader,
            pacingBitrate: pacingBitrate, progress: progress
        )

        await client.disconnect()
        let stats = await client.statistics
        print(
            "\n"
                + color.success(
                    "✓ Stream complete. Sent \(ProgressDisplay.formatBytes(stats.bytesSent))"
                ))
    }

    private func resolveBitrate(reader: AudioFileReader) -> Int {
        if let bitrate { return bitrate * 1000 }
        return reader.estimatedBitrate ?? 128_000
    }

    private func streamLoop(
        client: IcecastClient,
        reader: inout AudioFileReader,
        pacingBitrate: Int,
        progress: ProgressDisplay
    ) async throws {
        let chunkSize = 4096
        let sleepPerChunk = Double(chunkSize) / (Double(pacingBitrate) / 8.0)
        let startTime = Date()

        while true {
            if let chunk = try reader.readChunk(size: chunkSize) {
                try await client.send(chunk)
                let elapsed = Date().timeIntervalSince(startTime)
                let stats = await client.statistics
                let line = progress.formatStreamingStatus(
                    elapsed: elapsed, bytesSent: stats.bytesSent,
                    bitrate: stats.currentBitrate, title: title
                )
                print("\r\(line)", terminator: "")
                try await Task.sleep(
                    nanoseconds: UInt64(sleepPerChunk * 1_000_000_000)
                )
            } else if loop {
                try reader.reset()
            } else {
                break
            }
        }
    }
}
