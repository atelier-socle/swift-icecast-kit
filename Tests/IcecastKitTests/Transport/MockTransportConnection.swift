// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import IcecastKit

/// A fully controllable mock transport connection for testing.
///
/// Records all sent data, returns queued responses from `receive()`,
/// and allows configuring connect/send failures and timeouts.
actor MockTransportConnection: TransportConnection {

    /// Data that has been sent through this connection.
    private(set) var sentData: [Data] = []

    /// Queued responses to return from `receive()`.
    private var receiveQueue: [Data] = []

    /// If set, `connect()` will throw this error.
    var connectError: IcecastError?

    /// If set, `send()` will throw this error.
    var sendError: IcecastError?

    /// If set, `receive()` will throw this error.
    var receiveError: IcecastError?

    /// Tracks the current connection state.
    private(set) var connected: Bool = false

    /// Number of times `connect()` has been called.
    private(set) var connectCallCount: Int = 0

    /// Number of times `send()` has been called.
    private(set) var sendCallCount: Int = 0

    /// Number of times `receive()` has been called.
    private(set) var receiveCallCount: Int = 0

    /// Number of times `close()` has been called.
    private(set) var closeCallCount: Int = 0

    /// The host passed to the last `connect()` call.
    private(set) var lastConnectHost: String?

    /// The port passed to the last `connect()` call.
    private(set) var lastConnectPort: Int?

    /// The TLS flag passed to the last `connect()` call.
    private(set) var lastConnectUseTLS: Bool?

    /// Creates a new mock transport connection.
    init() {}

    /// Enqueues responses to be returned by subsequent `receive()` calls.
    ///
    /// - Parameter responses: The data items to enqueue.
    func enqueueResponses(_ responses: [Data]) {
        receiveQueue.append(contentsOf: responses)
    }

    /// Enqueues a single response to be returned by `receive()`.
    ///
    /// - Parameter response: The data to enqueue.
    func enqueueResponse(_ response: Data) {
        receiveQueue.append(response)
    }

    var isConnected: Bool {
        connected
    }

    func connect(host: String, port: Int, useTLS: Bool) async throws {
        connectCallCount += 1
        lastConnectHost = host
        lastConnectPort = port
        lastConnectUseTLS = useTLS

        if let error = connectError {
            throw error
        }

        connected = true
    }

    func send(_ data: Data) async throws {
        sendCallCount += 1

        guard connected else {
            throw IcecastError.notConnected
        }

        if let error = sendError {
            throw error
        }

        sentData.append(data)
    }

    func receive(maxBytes: Int) async throws -> Data {
        receiveCallCount += 1

        guard connected else {
            throw IcecastError.notConnected
        }

        if let error = receiveError {
            throw error
        }

        guard !receiveQueue.isEmpty else {
            throw IcecastError.connectionLost(reason: "No more queued responses")
        }

        let data = receiveQueue.removeFirst()
        if data.count > maxBytes {
            return data.prefix(maxBytes)
        }
        return data
    }

    func receive(maxBytes: Int, timeout: TimeInterval) async throws -> Data {
        try await receive(maxBytes: maxBytes)
    }

    func close() async {
        closeCallCount += 1
        connected = false
    }
}
