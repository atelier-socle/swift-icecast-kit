// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import ArgumentParser
import Foundation
import IcecastKit

/// Stream an audio file to an Icecast/SHOUTcast server.
///
/// Reads the audio file, connects to the server, and streams data
/// at approximately real-time pace based on bitrate.
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

    /// Auth password.
    @Option(name: .long, help: "Auth password")
    var password: String

    // MARK: - Stream Options

    /// Audio type override.
    @Option(name: .long, help: "Audio type: mp3, aac, ogg-vorbis, ogg-opus (default: auto-detect)")
    var contentType: String?

    /// Protocol mode.
    @Option(name: .long, help: "Protocol: auto, icecast-put, icecast-source, shoutcast-v1, shoutcast-v2:<id>")
    var `protocol`: String = "auto"

    /// Initial stream title.
    @Option(name: .long, help: "Initial stream title")
    var title: String?

    /// Bitrate in kbps for pacing.
    @Option(name: .long, help: "Bitrate in kbps for pacing (auto-detected if possible)")
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
        let config = try buildConfiguration(audioType: reader.contentType)
        let credentials = IcecastCredentials(username: username, password: password)
        let policy: ReconnectPolicy = noReconnect ? .none : .default
        let client = IcecastClient(configuration: config, credentials: credentials, reconnectPolicy: policy)

        try await connectAndStream(client: client, reader: &reader, progress: progress, color: color)
    }

    // MARK: - Private Helpers

    private func openAudioFile(color: ColorOutput) throws -> AudioFileReader {
        let audioType: AudioContentType? = try contentType.map { try parseContentType($0) }
        let reader = try AudioFileReader(path: file, contentType: audioType)
        print(color.info("📁 File: \(file) (\(ProgressDisplay.formatBytes(reader.fileSize)), \(reader.contentType.rawValue))"))
        return reader
    }

    private func buildConfiguration(audioType: AudioContentType) throws -> IcecastConfiguration {
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
        print(progress.formatConnected(host: host, port: port, mountpoint: mountpoint, protocolName: self.protocol))

        if let title {
            try await client.updateMetadata(ICYMetadata(streamTitle: title))
        }

        let pacingBitrate = resolveBitrate(reader: reader)
        try await streamLoop(client: client, reader: &reader, pacingBitrate: pacingBitrate, progress: progress)

        await client.disconnect()
        let stats = await client.statistics
        print("\n" + color.success("✓ Stream complete. Sent \(ProgressDisplay.formatBytes(stats.bytesSent))"))
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
                try await Task.sleep(nanoseconds: UInt64(sleepPerChunk * 1_000_000_000))
            } else if loop {
                try reader.reset()
            } else {
                break
            }
        }
    }
}
