// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - IcecastClient Recording Integration Tests

@Suite("IcecastClient — Recording Integration")
struct RecordingClientIntegrationTests {

    /// Creates a unique temporary directory.
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

    @Test("No recorder when recording config is nil")
    func noRecorderWhenNil() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test"
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try await client.connect()

        let stats = await client.recordingStatistics
        #expect(stats == nil)
        await client.disconnect()
    }

    @Test("startRecording starts recording dynamically")
    func startRecordingDynamic() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test"
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try await client.connect()
        try await client.startRecording(directory: dir)

        let stats = await client.recordingStatistics
        #expect(stats != nil)
        #expect(stats?.isRecording == true)
        await client.disconnect()
    }

    @Test("stopRecording returns statistics")
    func stopRecordingReturnsStats() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test"
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try await client.connect()
        try await client.startRecording(directory: dir)
        let stats = try await client.stopRecording()
        #expect(!stats.isRecording)
        #expect(stats.filesCreated >= 1)
        await client.disconnect()
    }

    @Test("recordingStarted event emitted")
    func recordingStartedEvent() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test"
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try await client.connect()

        let task = Task<Bool, Never> {
            for await event in client.events {
                if case .recordingStarted = event {
                    return true
                }
            }
            return false
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        try await client.startRecording(directory: dir)
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let found = await task.value
        #expect(found)
        await client.disconnect()
    }

    @Test("recordingStopped event emitted")
    func recordingStoppedEvent() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test"
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try await client.connect()
        try await client.startRecording(directory: dir)

        let task = Task<Bool, Never> {
            for await event in client.events {
                if case .recordingStopped = event {
                    return true
                }
            }
            return false
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        _ = try await client.stopRecording()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let found = await task.value
        #expect(found)
        await client.disconnect()
    }

    @Test("recordingStatistics returns nil when not recording")
    func statsNilWhenNotRecording() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test"
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try await client.connect()
        let stats = await client.recordingStatistics
        #expect(stats == nil)
        await client.disconnect()
    }

    @Test("Recording auto-starts when configuration has recording set")
    func autoStartRecording() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let recordConfig = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test",
            recording: recordConfig
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try await client.connect()

        let stats = await client.recordingStatistics
        #expect(stats != nil)
        #expect(stats?.isRecording == true)
        await client.disconnect()
    }

    @Test("send writes data to recorder when recording is active")
    func sendWritesToRecorder() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let recordConfig = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test",
            recording: recordConfig
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try await client.connect()
        try await client.send(Data([0x01, 0x02, 0x03]))

        let stats = await client.recordingStatistics
        #expect(stats?.bytesWritten == 3)
        await client.disconnect()
    }

    @Test("stopRecording when not recording returns empty stats")
    func stopRecordingWhenNotRecording() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test"
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try await client.connect()
        let stats = try await client.stopRecording()
        #expect(stats.bytesWritten == 0)
        #expect(!stats.isRecording)
        await client.disconnect()
    }

    @Test("disconnect stops active recording")
    func disconnectStopsRecording() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test"
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try await client.connect()
        try await client.startRecording(directory: dir)
        try await client.send(Data(repeating: 0xAA, count: 50))
        await client.disconnect()

        let stats = await client.recordingStatistics
        #expect(stats == nil)
    }

    @Test("recordingFileRotated event emitted on rotation via send")
    func fileRotatedEventOnSend() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let recordConfig = RecordingConfiguration(
            directory: dir,
            contentType: .mp3,
            maxFileSize: 50,
            filenamePattern: "rot_{index}"
        )
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test",
            recording: recordConfig
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try await client.connect()

        let task = Task<Bool, Never> {
            for await event in client.events {
                if case .recordingFileRotated = event {
                    return true
                }
            }
            return false
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        try await client.send(Data(repeating: 0xAA, count: 50))
        try await client.send(Data(repeating: 0xBB, count: 10))
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let found = await task.value
        #expect(found)
        await client.disconnect()
    }
}
