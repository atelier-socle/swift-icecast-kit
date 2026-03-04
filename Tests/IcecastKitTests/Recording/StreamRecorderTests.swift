// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - StreamRecorder Tests

@Suite("StreamRecorder")
struct StreamRecorderTests {

    /// Creates a unique temporary directory for each test.
    private func makeTempDir() throws -> String {
        let path = NSTemporaryDirectory() + "icecast-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true
        )
        return path
    }

    /// Cleans up a temporary directory.
    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test("start creates file in the configured directory")
    func startCreatesFile() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        let filePath = await recorder.currentFilePath
        #expect(filePath != nil)
        #expect(FileManager.default.fileExists(atPath: filePath ?? ""))
        _ = try await recorder.stop()
    }

    @Test("start creates directory if it does not exist")
    func startCreatesDirectory() async throws {
        let base = NSTemporaryDirectory()
        let dir = base + "icecast-test-\(UUID().uuidString)/sub/deep"
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: dir, isDirectory: &isDir
        )
        #expect(exists)
        #expect(isDir.boolValue)
        _ = try await recorder.stop()
    }

    @Test("start throws if already recording")
    func startThrowsIfAlreadyRecording() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        await #expect(throws: IcecastError.self) {
            try await recorder.start()
        }
        _ = try await recorder.stop()
    }

    @Test("write is a no-op if not started")
    func writeNoOpIfNotStarted() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.write(Data([0x01, 0x02]))

        let stats = await recorder.statistics
        #expect(stats.bytesWritten == 0)
    }

    @Test("write writes bytes to the file")
    func writeWritesBytes() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        try await recorder.write(data)

        let stats = await recorder.statistics
        #expect(stats.bytesWritten == 5)

        let finalStats = try await recorder.stop()
        let filePath = finalStats.currentFilePath
        #expect(filePath != nil)
        let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath ?? ""))
        #expect(fileData == data)
    }

    @Test("stop flushes and closes the file")
    func stopFlushesAndCloses() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()
        try await recorder.write(Data(repeating: 0xAB, count: 100))

        let stats = try await recorder.stop()
        #expect(stats.bytesWritten == 100)
        #expect(stats.filesCreated == 1)
        #expect(!stats.isRecording)
    }

    @Test("stop returns coherent statistics")
    func stopReturnsStats() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .aac
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()
        try await recorder.write(Data(repeating: 0x00, count: 50))
        try await recorder.write(Data(repeating: 0x01, count: 30))

        let stats = try await recorder.stop()
        #expect(stats.bytesWritten == 80)
        #expect(stats.filesCreated == 1)
        #expect(stats.duration >= 0)
        #expect(stats.currentFilePath != nil)
    }

    @Test("isRecording reflects start/stop state")
    func isRecordingState() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        var isRec = await recorder.isRecording
        #expect(!isRec)

        try await recorder.start()
        isRec = await recorder.isRecording
        #expect(isRec)

        _ = try await recorder.stop()
        isRec = await recorder.isRecording
        #expect(!isRec)
    }

    @Test("Rotation by size creates new file when maxFileSize reached")
    func rotationBySize() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            maxFileSize: 100,
            filenamePattern: "rec_{index}"
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        try await recorder.write(Data(repeating: 0xAA, count: 100))
        try await recorder.write(Data(repeating: 0xBB, count: 10))

        let stats = try await recorder.stop()
        #expect(stats.filesCreated == 2)
    }

    @Test("Rotation by duration creates new file when splitInterval reached")
    func rotationByDuration() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            splitInterval: 0.05,
            filenamePattern: "rec_{index}"
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        try await Task.sleep(nanoseconds: 60_000_000)
        try await recorder.write(Data(repeating: 0xCC, count: 10))

        let stats = try await recorder.stop()
        #expect(stats.filesCreated == 2)
    }

    @Test("filesCreated increments with each rotation")
    func filesCreatedIncrements() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            maxFileSize: 50,
            filenamePattern: "rec_{index}"
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        for _ in 0..<3 {
            try await recorder.write(Data(repeating: 0xFF, count: 50))
        }
        try await recorder.write(Data(repeating: 0x00, count: 1))

        let stats = try await recorder.stop()
        #expect(stats.filesCreated == 4)
    }

    @Test("{date} token resolved in filename")
    func dateTokenResolved() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            filenamePattern: "{date}_test"
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        let filePath = await recorder.currentFilePath ?? ""
        let filename = (filePath as NSString).lastPathComponent
        #expect(!filename.contains("{date}"))
        #expect(filename.contains("_test"))
        _ = try await recorder.stop()
    }

    @Test("{mountpoint} token resolved in filename")
    func mountpointTokenResolved() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            filenamePattern: "{mountpoint}_rec"
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start(mountpoint: "/live.mp3")

        let filePath = await recorder.currentFilePath ?? ""
        let filename = (filePath as NSString).lastPathComponent
        #expect(filename.contains("live_mp3"))
        #expect(!filename.contains("{mountpoint}"))
        _ = try await recorder.stop()
    }

    @Test("{index} token resolved in filename")
    func indexTokenResolved() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            filenamePattern: "rec_{index}"
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        let filePath = await recorder.currentFilePath ?? ""
        let filename = (filePath as NSString).lastPathComponent
        #expect(filename.hasPrefix("rec_1"))
        _ = try await recorder.stop()
    }

    @Test("matchSource format uses correct extension for each content type")
    func matchSourceExtension() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let types: [(AudioContentType, String)] = [
            (.mp3, ".mp3"),
            (.aac, ".aac"),
            (.oggVorbis, ".ogg"),
            (.oggOpus, ".opus")
        ]

        for (contentType, ext) in types {
            let subdir = dir + "/\(contentType.fileExtension)"
            let config = RecordingConfiguration(
                directory: subdir,
                contentType: contentType,
                format: .matchSource
            )
            let recorder = StreamRecorder(configuration: config)
            try await recorder.start()
            let path = await recorder.currentFilePath ?? ""
            #expect(path.hasSuffix(ext))
            _ = try await recorder.stop()
        }
    }

    @Test("raw format uses .raw extension")
    func rawFormatExtension() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            format: .raw
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        let filePath = await recorder.currentFilePath ?? ""
        #expect(filePath.hasSuffix(".raw"))
        _ = try await recorder.stop()
    }

    @Test("Flush timer is cancelled on stop")
    func flushTimerCancelled() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            flushInterval: 0.05
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()
        try await recorder.write(Data(repeating: 0x42, count: 10))
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = try await recorder.stop()

        let isRec = await recorder.isRecording
        #expect(!isRec)
    }

    @Test("statistics.bytesWritten matches actual bytes written")
    func bytesWrittenAccuracy() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start()

        var total = 0
        for size in [10, 20, 30, 40] {
            try await recorder.write(Data(repeating: 0x00, count: size))
            total += size
        }

        let stats = await recorder.statistics
        #expect(stats.bytesWritten == Int64(total))
        _ = try await recorder.stop()
    }

    @Test("start throws when directory path is a file, not a directory")
    func startThrowsWhenPathIsFile() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let filePath = dir + "/notadir"
        FileManager.default.createFile(atPath: filePath, contents: nil)

        let config = RecordingConfiguration(
            directory: filePath, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        await #expect(throws: IcecastError.self) {
            try await recorder.start()
        }
    }

    @Test("start throws when directory is not writable")
    func startThrowsWhenNotWritable() async throws {
        let dir = try makeTempDir()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: dir
            )
            cleanup(dir)
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444], ofItemAtPath: dir
        )

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        await #expect(throws: IcecastError.self) {
            try await recorder.start()
        }
    }

    @Test("start throws when directory cannot be created")
    func startThrowsWhenCannotCreateDir() async throws {
        let config = RecordingConfiguration(
            directory: "/proc/nonexistent/path", contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        await #expect(throws: IcecastError.self) {
            try await recorder.start()
        }
    }

    @Test("empty mountpoint resolves to stream in filename")
    func emptyMountpointResolvesToStream() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            filenamePattern: "{mountpoint}_rec"
        )
        let recorder = StreamRecorder(configuration: config)
        try await recorder.start(mountpoint: "")

        let filePath = await recorder.currentFilePath ?? ""
        let filename = (filePath as NSString).lastPathComponent
        #expect(filename.contains("stream"))
        _ = try await recorder.stop()
    }

    @Test("stop when not recording returns empty statistics")
    func stopWhenNotRecording() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        let stats = try await recorder.stop()
        #expect(stats.bytesWritten == 0)
        #expect(stats.filesCreated == 0)
        #expect(!stats.isRecording)
    }

    @Test("currentFilePath is nil when not recording")
    func currentFilePathNilWhenNotRecording() async {
        let config = RecordingConfiguration(
            directory: "/tmp", contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: config)
        let path = await recorder.currentFilePath
        #expect(path == nil)
    }
}
