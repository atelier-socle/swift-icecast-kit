// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Showcase — Recording")
struct RecordingShowcaseTests {

    private func makeTempDir() throws -> String {
        let path = NSTemporaryDirectory() + "icecast-showcase-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true
        )
        return path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Showcase 1: Recorder creates file on start

    @Test("Recorder creates file in the configured directory on start")
    func recorderCreatesFileOnStart() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3,
            flushInterval: 0
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        let path = await recorder.currentFilePath
        #expect(path != nil)
        #expect(FileManager.default.fileExists(atPath: path ?? ""))
        _ = try await recorder.stop()
    }

    // MARK: - Showcase 2: write() accumulates bytes

    @Test("Recorder accumulates bytes correctly across writes")
    func recorderAccumulatesBytesCorrectly() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3,
            flushInterval: 0
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        let data = Data(repeating: 0xFF, count: 1000)
        try await recorder.write(data)
        try await recorder.write(data)

        let stats = try await recorder.stop()
        #expect(stats.bytesWritten == 2000)
    }

    // MARK: - Showcase 3: stop() returns coherent statistics

    @Test("Recorder stop returns coherent statistics")
    func recorderStopReturnsCoherentStatistics() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3,
            flushInterval: 0
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        let data = Data(repeating: 0xAB, count: 512)
        try await recorder.write(data)

        let stats = try await recorder.stop()
        #expect(stats.bytesWritten == 512)
        #expect(stats.filesCreated == 1)
        #expect(stats.duration >= 0)
        #expect(stats.isRecording == false)
    }

    // MARK: - Showcase 4: Rotation by max file size

    @Test("File rotation triggered by maxFileSize")
    func rotationTriggeredByMaxSize() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3,
            maxFileSize: 500,
            flushInterval: 0
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        // Write more than maxFileSize to trigger rotation
        let data = Data(repeating: 0xFF, count: 600)
        try await recorder.write(data)

        let stats = try await recorder.stop()
        #expect(stats.filesCreated == 2)
    }

    // MARK: - Showcase 5: Filename tokens resolved

    @Test("Filename tokens {date}, {mountpoint}, {index} resolved correctly")
    func filenameTokensResolvedCorrectly() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3,
            flushInterval: 0,
            filenamePattern: "{mountpoint}_{index}"
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start(mountpoint: "/live.mp3")

        let path = await recorder.currentFilePath
        #expect(path?.contains("live_mp3") == true)
        #expect(path?.contains("_1") == true)
        _ = try await recorder.stop()
    }

    // MARK: - Showcase 6: matchSource format uses correct extension

    @Test("matchSource format uses correct extension per content type")
    func matchSourceFormatUsesCorrectExtension() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        for (contentType, ext) in [
            (AudioContentType.mp3, "mp3"),
            (AudioContentType.aac, "aac"),
            (AudioContentType.oggVorbis, "ogg"),
            (AudioContentType.oggOpus, "opus")
        ] {
            let config = RecordingConfiguration(
                directory: dir, contentType: contentType,
                format: .matchSource,
                flushInterval: 0
            )
            let recorder = StreamRecorder(configuration: config)
            try await recorder.start()
            let path = await recorder.currentFilePath ?? ""
            #expect(path.hasSuffix(".\(ext)"))
            _ = try await recorder.stop()
        }
    }

    // MARK: - Showcase 7: Raw format uses .raw extension

    @Test("Raw recording format uses .raw extension")
    func rawFormatUsesRawExtension() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3,
            format: .raw,
            flushInterval: 0
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        let path = await recorder.currentFilePath ?? ""
        #expect(path.hasSuffix(".raw"))
        _ = try await recorder.stop()
    }

    // MARK: - Showcase 8: Recorder standalone (no client)

    @Test("Recorder works standalone without IcecastClient")
    func recorderWorksStandaloneWithoutClient() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .aac,
            flushInterval: 0
        )
        let recorder = StreamRecorder(configuration: config)

        #expect(await recorder.isRecording == false)
        try await recorder.start()
        #expect(await recorder.isRecording == true)

        let data = Data(repeating: 0xCD, count: 2048)
        try await recorder.write(data)

        let stats = await recorder.statistics
        #expect(stats.bytesWritten == 2048)

        let final = try await recorder.stop()
        #expect(final.bytesWritten == 2048)
        #expect(await recorder.isRecording == false)
    }

    // MARK: - Showcase 9: RecordingStatistics fields

    @Test("RecordingStatistics reports all expected fields")
    func recordingStatisticsAllFields() {
        let stats = RecordingStatistics(
            duration: 60.0,
            bytesWritten: 1_000_000,
            filesCreated: 3,
            currentFilePath: "/tmp/test.mp3",
            isRecording: true
        )
        #expect(stats.duration == 60.0)
        #expect(stats.bytesWritten == 1_000_000)
        #expect(stats.filesCreated == 3)
        #expect(stats.currentFilePath == "/tmp/test.mp3")
        #expect(stats.isRecording == true)
    }

    // MARK: - Showcase 10: FileRotationPolicy configuration

    @Test("FileRotationPolicy respects maxSize and splitInterval")
    func fileRotationPolicyConfiguration() {
        let policy = FileRotationPolicy(
            maxFileSize: 50_000_000,
            splitInterval: 3600
        )
        #expect(!policy.shouldRotate(currentSize: 100, currentDuration: 10))
        #expect(policy.shouldRotate(currentSize: 50_000_001, currentDuration: 10))
        #expect(policy.shouldRotate(currentSize: 100, currentDuration: 3601))
    }

    // MARK: - Showcase 11: Mountpoint sanitization in filenames

    @Test("Mountpoint is sanitized for safe filenames")
    func mountpointSanitizedInFilename() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3,
            flushInterval: 0,
            filenamePattern: "{mountpoint}"
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start(mountpoint: "/live/stream.mp3")

        let path = await recorder.currentFilePath ?? ""
        // Slashes and dots replaced with underscores
        #expect(path.contains("live_stream_mp3"))
        _ = try await recorder.stop()
    }
}
