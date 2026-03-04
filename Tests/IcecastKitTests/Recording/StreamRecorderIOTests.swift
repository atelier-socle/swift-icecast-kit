// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - File Handling Stubs

/// Stub file handle that always succeeds.
struct StubFileHandle: FileHandling, Sendable {
    func write(contentsOf data: Data) throws {}
    func synchronize() throws {}
    func close() throws {}
}

/// File handle that throws on `write(contentsOf:)`.
struct FailingWriteFileHandle: FileHandling, Sendable {
    func write(contentsOf data: Data) throws {
        throw NSError(
            domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError
        )
    }
    func synchronize() throws {}
    func close() throws {}
}

/// File handle that throws on `close()`.
struct FailingCloseFileHandle: FileHandling, Sendable {
    func write(contentsOf data: Data) throws {}
    func synchronize() throws {}
    func close() throws {
        throw NSError(
            domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError
        )
    }
}

/// File handle that throws on `synchronize()`.
struct FailingSyncFileHandle: FileHandling, Sendable {
    func write(contentsOf data: Data) throws {}
    func synchronize() throws {
        throw NSError(
            domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError
        )
    }
    func close() throws {}
}

/// Factory that returns a fixed handle and always creates files successfully.
struct FixedHandleFactory: FileHandlingFactory, Sendable {
    let handle: any FileHandling
    func open(forWritingAtPath path: String) -> (any FileHandling)? { handle }
    func createFile(atPath path: String) -> Bool { true }
}

/// Factory that always fails `createFile`.
struct FailingCreateFactory: FileHandlingFactory, Sendable {
    func open(forWritingAtPath path: String) -> (any FileHandling)? { nil }
    func createFile(atPath path: String) -> Bool { false }
}

/// Factory that creates the file but fails to open it.
struct FailingOpenFactory: FileHandlingFactory, Sendable {
    func open(forWritingAtPath path: String) -> (any FileHandling)? { nil }
    func createFile(atPath path: String) -> Bool { true }
}

/// Factory that only creates files whose path ends with a given suffix.
/// Used to simulate `createFile` succeeding on the first file but
/// failing during rotation when a new file path is generated.
struct SucceedOnceCreateFactory: FileHandlingFactory, Sendable {
    let handle: any FileHandling
    let allowedSuffix: String
    func open(forWritingAtPath path: String) -> (any FileHandling)? { handle }
    func createFile(atPath path: String) -> Bool {
        path.hasSuffix(allowedSuffix)
    }
}

// MARK: - StreamRecorder I/O Error Tests

@Suite("StreamRecorder — I/O Error Paths")
struct StreamRecorderIOErrorTests {

    private func makeTempDir() throws -> String {
        let path = NSTemporaryDirectory() + "icecast-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true
        )
        return path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test("write throws recordingFailed when FileHandle.write fails")
    func writeThrowsOnFileHandleError() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let factory = FixedHandleFactory(handle: FailingWriteFileHandle())
        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(
            configuration: config, fileFactory: factory
        )
        try await recorder.start()

        await #expect(throws: IcecastError.self) {
            try await recorder.write(Data([0x01, 0x02]))
        }
    }

    @Test("stop throws recordingFailed when FileHandle.close fails")
    func stopThrowsOnCloseError() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let factory = FixedHandleFactory(handle: FailingCloseFileHandle())
        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(
            configuration: config, fileFactory: factory
        )
        try await recorder.start()

        await #expect(throws: IcecastError.self) {
            _ = try await recorder.stop()
        }

        let isRec = await recorder.isRecording
        #expect(!isRec)
    }

    @Test("stop throws recordingFailed when synchronize fails")
    func stopThrowsOnSyncError() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let factory = FixedHandleFactory(handle: FailingSyncFileHandle())
        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(
            configuration: config, fileFactory: factory
        )
        try await recorder.start()

        await #expect(throws: IcecastError.self) {
            _ = try await recorder.stop()
        }
    }

    @Test("createFile returns false throws recordingFailed")
    func createFileFailure() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(
            configuration: config, fileFactory: FailingCreateFactory()
        )
        await #expect(throws: IcecastError.self) {
            try await recorder.start()
        }
    }

    @Test("open returns nil throws recordingFailed")
    func openFileFailure() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let config = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(
            configuration: config, fileFactory: FailingOpenFactory()
        )
        await #expect(throws: IcecastError.self) {
            try await recorder.start()
        }
    }

    @Test("rotation fails when close of current file fails")
    func rotationFailsOnClose() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let factory = FixedHandleFactory(handle: FailingCloseFileHandle())
        let config = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            maxFileSize: 50,
            filenamePattern: "rot_{index}"
        )
        let recorder = StreamRecorder(
            configuration: config, fileFactory: factory
        )
        try await recorder.start()

        await #expect(throws: IcecastError.self) {
            try await recorder.write(Data(repeating: 0xAA, count: 50))
        }
    }

    @Test("rotation fails when new file cannot be created")
    func rotationFailsOnNewFile() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let factory = SucceedOnceCreateFactory(
            handle: StubFileHandle(),
            allowedSuffix: "rot_1.mp3"
        )
        let config = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            maxFileSize: 50,
            filenamePattern: "rot_{index}"
        )
        let recorder = StreamRecorder(
            configuration: config, fileFactory: factory
        )
        try await recorder.start()

        await #expect(throws: IcecastError.self) {
            try await recorder.write(Data(repeating: 0xAA, count: 50))
        }
    }
}
