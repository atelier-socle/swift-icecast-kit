// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Transport Connection")
struct TransportConnectionTests {

    // MARK: - Connect / Disconnect Lifecycle

    @Test("Mock transport connects successfully")
    func mockConnectsSuccessfully() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        let connected = await mock.isConnected
        #expect(connected)
    }

    @Test("Mock transport records connect parameters")
    func mockRecordsConnectParameters() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "radio.example.com", port: 8443, useTLS: true)
        let host = await mock.lastConnectHost
        let port = await mock.lastConnectPort
        let tls = await mock.lastConnectUseTLS
        #expect(host == "radio.example.com")
        #expect(port == 8443)
        #expect(tls == true)
    }

    @Test("Mock transport tracks connect call count")
    func mockTracksConnectCallCount() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        let count = await mock.connectCallCount
        #expect(count == 1)
    }

    @Test("Mock transport disconnects on close")
    func mockDisconnectsOnClose() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.close()
        let connected = await mock.isConnected
        #expect(!connected)
    }

    @Test("Mock transport tracks close call count")
    func mockTracksCloseCallCount() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.close()
        let count = await mock.closeCallCount
        #expect(count == 1)
    }

    // MARK: - Send

    @Test("Mock transport records sent data correctly")
    func mockRecordsSentData() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        let testData = Data("Hello, Icecast!".utf8)
        try await mock.send(testData)
        let sentData = await mock.sentData
        #expect(sentData == [testData])
    }

    @Test("Mock transport tracks send call count")
    func mockTracksSendCallCount() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        try await mock.send(Data("data1".utf8))
        try await mock.send(Data("data2".utf8))
        let count = await mock.sendCallCount
        #expect(count == 2)
    }

    @Test("Mock transport records multiple sends")
    func mockRecordsMultipleSends() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        let d1 = Data("first".utf8)
        let d2 = Data("second".utf8)
        try await mock.send(d1)
        try await mock.send(d2)
        let sentData = await mock.sentData
        #expect(sentData.count == 2)
        #expect(sentData[0] == d1)
        #expect(sentData[1] == d2)
    }

    // MARK: - Receive

    @Test("Mock transport returns queued responses")
    func mockReturnsQueuedResponses() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        let response = Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        await mock.enqueueResponse(response)
        let received = try await mock.receive(maxBytes: 4096)
        #expect(received == response)
    }

    @Test("Mock transport returns multiple queued responses in order")
    func mockReturnsMultipleResponses() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        let r1 = Data("first".utf8)
        let r2 = Data("second".utf8)
        await mock.enqueueResponses([r1, r2])
        let received1 = try await mock.receive(maxBytes: 4096)
        let received2 = try await mock.receive(maxBytes: 4096)
        #expect(received1 == r1)
        #expect(received2 == r2)
    }

    @Test("Mock transport tracks receive call count")
    func mockTracksReceiveCallCount() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("data".utf8))
        _ = try await mock.receive(maxBytes: 4096)
        let count = await mock.receiveCallCount
        #expect(count == 1)
    }

    @Test("Mock transport receive with timeout returns data")
    func mockReceiveWithTimeout() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        let response = Data("response".utf8)
        await mock.enqueueResponse(response)
        let received = try await mock.receive(maxBytes: 4096, timeout: 5.0)
        #expect(received == response)
    }

    // MARK: - Connect Failure

    @Test("Mock transport propagates connect error")
    func mockPropagatesConnectError() async {
        let mock = MockTransportConnection()
        await mock.setConnectError(.connectionFailed(host: "bad", port: 0, reason: "refused"))
        await #expect(throws: IcecastError.self) {
            try await mock.connect(host: "bad", port: 0, useTLS: false)
        }
    }

    @Test("Mock transport remains disconnected after connect failure")
    func mockRemainsDisconnectedAfterConnectFailure() async {
        let mock = MockTransportConnection()
        await mock.setConnectError(.connectionFailed(host: "bad", port: 0, reason: "refused"))
        try? await mock.connect(host: "bad", port: 0, useTLS: false)
        let connected = await mock.isConnected
        #expect(!connected)
    }

    // MARK: - Send Failure

    @Test("Mock transport propagates send error")
    func mockPropagatesSendError() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.setSendError(.sendFailed(reason: "broken pipe"))
        await #expect(throws: IcecastError.self) {
            try await mock.send(Data("data".utf8))
        }
    }

    // MARK: - State Tracking

    @Test("Mock transport isConnected reflects connection state")
    func mockIsConnectedTracksState() async throws {
        let mock = MockTransportConnection()
        let before = await mock.isConnected
        #expect(!before)
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        let during = await mock.isConnected
        #expect(during)
        await mock.close()
        let after = await mock.isConnected
        #expect(!after)
    }

    // MARK: - Factory

    @Test("Factory creates correct transport type for platform")
    func factoryCreatesCorrectType() {
        let transport = TransportConnectionFactory.makeConnection()
        #if canImport(Network)
            #expect(transport is NWTransportConnection)
        #else
            #expect(transport is POSIXTransportConnection)
        #endif
    }

    // MARK: - Edge Cases

    @Test("Double close is safe and idempotent")
    func doubleCloseIsSafe() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.close()
        await mock.close()
        let count = await mock.closeCallCount
        #expect(count == 2)
        let connected = await mock.isConnected
        #expect(!connected)
    }

    @Test("Send after close throws notConnected")
    func sendAfterCloseThrows() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.close()
        await #expect(throws: IcecastError.self) {
            try await mock.send(Data("data".utf8))
        }
    }

    @Test("Receive after close throws notConnected")
    func receiveAfterCloseThrows() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("data".utf8))
        await mock.close()
        await #expect(throws: IcecastError.self) {
            try await mock.receive(maxBytes: 4096)
        }
    }

    @Test("Send without connecting throws notConnected")
    func sendWithoutConnectingThrows() async {
        let mock = MockTransportConnection()
        await #expect(throws: IcecastError.self) {
            try await mock.send(Data("data".utf8))
        }
    }

    @Test("Receive without connecting throws notConnected")
    func receiveWithoutConnectingThrows() async {
        let mock = MockTransportConnection()
        await #expect(throws: IcecastError.self) {
            try await mock.receive(maxBytes: 4096)
        }
    }

    @Test("Large data send (1MB) is recorded correctly")
    func largeSendIsRecorded() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        let largeData = Data(repeating: 0xFF, count: 1_048_576)
        try await mock.send(largeData)
        let sentData = await mock.sentData
        #expect(sentData.first?.count == 1_048_576)
    }

    @Test("Empty data send is recorded")
    func emptySendIsRecorded() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        try await mock.send(Data())
        let sentData = await mock.sentData
        #expect(sentData.count == 1)
        #expect(sentData[0].isEmpty)
    }

    @Test("Receive with no queued responses throws connection lost")
    func receiveEmptyQueueThrows() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await #expect(throws: IcecastError.self) {
            try await mock.receive(maxBytes: 4096)
        }
    }

    @Test("Mock transport propagates receive error")
    func mockPropagatesReceiveError() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.setReceiveError(.connectionTimeout(seconds: 5.0))
        await #expect(throws: IcecastError.self) {
            try await mock.receive(maxBytes: 4096)
        }
    }

    @Test("Multiple sequential connects track call count")
    func multipleSequentialConnects() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "host1", port: 8000, useTLS: false)
        await mock.close()
        try await mock.connect(host: "host2", port: 8001, useTLS: true)
        let count = await mock.connectCallCount
        let host = await mock.lastConnectHost
        #expect(count == 2)
        #expect(host == "host2")
    }

    @Test("Receive respects maxBytes limit")
    func receiveRespectsMaxBytes() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        let largeResponse = Data(repeating: 0xAB, count: 1000)
        await mock.enqueueResponse(largeResponse)
        let received = try await mock.receive(maxBytes: 100)
        #expect(received.count == 100)
    }
}

// MARK: - Mock Helpers

extension MockTransportConnection {
    func setConnectError(_ error: IcecastError?) {
        self.connectError = error
    }

    func setSendError(_ error: IcecastError?) {
        self.sendError = error
    }

    func setReceiveError(_ error: IcecastError?) {
        self.receiveError = error
    }
}
