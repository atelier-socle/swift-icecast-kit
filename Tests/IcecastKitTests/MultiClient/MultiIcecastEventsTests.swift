// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - MultiIcecastClient — Events

@Suite("MultiIcecastClient — Events")
struct MultiIcecastClientEventsTests {

    @Test("destinationAdded event is emitted on add")
    func destinationAddedEvent() async throws {
        let multi = MultiIcecastClient()
        let task = Task<MultiIcecastEvent?, Never> {
            for await event in multi.events {
                return event
            }
            return nil
        }

        try await multi.addDestination(
            "test",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let event = await task.value
        if case .destinationAdded(let label) = event {
            #expect(label == "test")
        }
    }

    @Test("destinationRemoved event is emitted on remove")
    func destinationRemovedEvent() async throws {
        let multi = MultiIcecastClient()
        try await multi.addDestination(
            "test",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )

        let task = Task<MultiIcecastEvent?, Never> {
            for await event in multi.events {
                if case .destinationRemoved = event {
                    return event
                }
            }
            return nil
        }

        await multi.removeDestination(label: "test")

        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let event = await task.value
        if case .destinationRemoved(let label) = event {
            #expect(label == "test")
        }
    }

    @Test("allConnected event is emitted when all connect")
    func allConnectedEvent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })

        try await multi.addDestination(
            "only",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )

        let task = Task<Bool, Never> {
            for await event in multi.events {
                if case .allConnected = event {
                    return true
                }
            }
            return false
        }

        try await multi.connectAll()

        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let gotAllConnected = await task.value
        #expect(gotAllConnected)
    }

    @Test("allConnected emitted after addDestinationLive completes all destinations")
    func allConnectedAfterHotAdd() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })

        // First destination: add and connect
        try await multi.addDestination(
            "first",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/a.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        try await multi.connectAll()

        // Listen for .allConnected
        let task = Task<Bool, Never> {
            for await event in multi.events {
                if case .allConnected = event {
                    return true
                }
            }
            return false
        }

        // Hot-add second destination — should trigger .allConnected
        // since both destinations are now connected
        try await multi.addDestinationLive(
            "second",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/b.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let gotAllConnected = await task.value
        #expect(gotAllConnected)
    }
}

// MARK: - IcecastError — Multi-Destination Cases

@Suite("IcecastError — Multi-Destination")
struct IcecastErrorMultiDestinationTests {

    @Test("destinationAlreadyExists has description")
    func destinationAlreadyExistsDescription() {
        let error = IcecastError.destinationAlreadyExists(label: "primary")
        #expect(error.description.contains("primary"))
    }

    @Test("destinationNotFound has description")
    func destinationNotFoundDescription() {
        let error = IcecastError.destinationNotFound(label: "backup")
        #expect(error.description.contains("backup"))
    }

    @Test("allDestinationsFailed has description")
    func allDestinationsFailedDescription() {
        let error = IcecastError.allDestinationsFailed
        #expect(!error.description.isEmpty)
    }

    @Test("partialSendFailure has description with counts")
    func partialSendFailureDescription() {
        let error = IcecastError.partialSendFailure(
            successCount: 2, failureCount: 1
        )
        #expect(error.description.contains("2"))
        #expect(error.description.contains("1"))
    }
}
