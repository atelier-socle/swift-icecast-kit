// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

/// Thread-safe event collector for testing async event streams.
private actor MonitorEventCollector {
    var events: [ConnectionEvent] = []

    func append(_ event: ConnectionEvent) {
        events.append(event)
    }
}

@Suite("ConnectionMonitor — Bytes and Statistics")
struct ConnectionMonitorBytesTests {

    @Test("recordBytesSent updates bytesSent")
    func recordBytesSentUpdatesBytes() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordBytesSent(100)
        let stats = await monitor.statistics
        #expect(stats.bytesSent == 100)
    }

    @Test("recordBytesSent updates bytesTotal")
    func recordBytesSentUpdatesBytesTotal() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordBytesSent(200)
        let stats = await monitor.statistics
        #expect(stats.bytesTotal == 200)
    }

    @Test("Multiple recordBytesSent calls accumulate")
    func multipleRecordBytesSentAccumulate() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordBytesSent(100)
        await monitor.recordBytesSent(200)
        await monitor.recordBytesSent(300)
        let stats = await monitor.statistics
        #expect(stats.bytesSent == 600)
        #expect(stats.bytesTotal == 600)
    }

    @Test("averageBitrate computed correctly")
    func averageBitrateComputed() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.markConnected()
        await monitor.recordBytesSent(1000)
        try await Task.sleep(nanoseconds: 100_000_000)
        let stats = await monitor.statistics
        #expect(stats.averageBitrate > 0)
        #expect(stats.duration > 0)
    }

    @Test("currentBitrate reflects recent sends")
    func currentBitrateReflectsRecentSends() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordBytesSent(500)
        try await Task.sleep(nanoseconds: 50_000_000)
        await monitor.recordBytesSent(500)
        let stats = await monitor.statistics
        #expect(stats.currentBitrate > 0)
    }

    @Test("duration increases while connected")
    func durationIncreasesWhileConnected() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.markConnected()
        try await Task.sleep(nanoseconds: 100_000_000)
        let stats = await monitor.statistics
        #expect(stats.duration > 0)
    }

    @Test("connectedSince set by markConnected")
    func connectedSinceSetByMarkConnected() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.markConnected()
        let stats = await monitor.statistics
        #expect(stats.connectedSince != nil)
    }

    @Test("connectedSince cleared by markDisconnected")
    func connectedSinceClearedByMarkDisconnected() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.markConnected()
        await monitor.markDisconnected()
        let stats = await monitor.statistics
        #expect(stats.connectedSince == nil)
    }
}

@Suite("ConnectionMonitor — Counters")
struct ConnectionMonitorCounterTests {

    @Test("recordMetadataUpdate increments metadataUpdateCount")
    func recordMetadataUpdateIncrements() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordMetadataUpdate()
        let stats = await monitor.statistics
        #expect(stats.metadataUpdateCount == 1)
    }

    @Test("recordReconnection increments reconnectionCount")
    func recordReconnectionIncrements() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordReconnection()
        let stats = await monitor.statistics
        #expect(stats.reconnectionCount == 1)
    }

    @Test("recordSendError increments sendErrorCount")
    func recordSendErrorIncrements() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordSendError()
        let stats = await monitor.statistics
        #expect(stats.sendErrorCount == 1)
    }

    @Test("Multiple counter increments accumulate correctly")
    func multipleCounterIncrements() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordMetadataUpdate()
        await monitor.recordMetadataUpdate()
        await monitor.recordMetadataUpdate()
        await monitor.recordReconnection()
        await monitor.recordReconnection()
        await monitor.recordSendError()
        let stats = await monitor.statistics
        #expect(stats.metadataUpdateCount == 3)
        #expect(stats.reconnectionCount == 2)
        #expect(stats.sendErrorCount == 1)
    }
}

@Suite("ConnectionMonitor — Reset")
struct ConnectionMonitorResetTests {

    @Test("reset clears all statistics to zero")
    func resetClearsStatistics() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordBytesSent(1000)
        await monitor.recordMetadataUpdate()
        await monitor.recordReconnection()
        await monitor.recordSendError()
        await monitor.reset()
        let stats = await monitor.statistics
        #expect(stats.bytesSent == 0)
        #expect(stats.bytesTotal == 0)
        #expect(stats.metadataUpdateCount == 0)
        #expect(stats.reconnectionCount == 0)
        #expect(stats.sendErrorCount == 0)
    }

    @Test("reset clears connectedSince")
    func resetClearsConnectedSince() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.markConnected()
        await monitor.reset()
        let stats = await monitor.statistics
        #expect(stats.connectedSince == nil)
    }

    @Test("reset stops periodic stats emission")
    func resetStopsPeriodicEmission() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: 0.05)
        await monitor.markConnected()
        await monitor.reset()
        let collector = MonitorEventCollector()
        let task = Task {
            for await event in monitor.events {
                await collector.append(event)
            }
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        let events = await collector.events
        let statsEvents = events.filter {
            if case .statistics = $0 { return true }
            return false
        }
        #expect(statsEvents.isEmpty)
    }

    @Test("After reset, new recordBytesSent starts from zero")
    func afterResetNewBytesStartFromZero() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordBytesSent(500)
        await monitor.reset()
        await monitor.recordBytesSent(100)
        let stats = await monitor.statistics
        #expect(stats.bytesSent == 100)
    }
}

@Suite("ConnectionMonitor — Event Emission")
struct ConnectionMonitorEventTests {

    @Test("emit delivers events to the AsyncStream")
    func emitDeliversEvents() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        let collector = MonitorEventCollector()
        let task = Task {
            for await event in monitor.events {
                await collector.append(event)
            }
        }
        await monitor.emit(.connected(host: "h", port: 8000, mountpoint: "/m", protocolName: "p"))
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        #expect(events.count >= 1)
    }

    @Test("Multiple events delivered in order")
    func multipleEventsDeliveredInOrder() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        let collector = MonitorEventCollector()
        let task = Task {
            for await event in monitor.events {
                await collector.append(event)
            }
        }
        await monitor.emit(.connected(host: "h", port: 8000, mountpoint: "/m", protocolName: "p"))
        await monitor.emit(.disconnected(reason: .requested))
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        #expect(events.count >= 2)
        if events.count >= 2 {
            if case .connected = events[0] {
            } else {
                Issue.record("Expected connected event first")
            }
            if case .disconnected = events[1] {
            } else {
                Issue.record("Expected disconnected event second")
            }
        }
    }

    @Test("Events are received by consumers iterating the stream")
    func eventsReceivedByConsumers() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        let collector = MonitorEventCollector()
        let task = Task {
            for await event in monitor.events {
                await collector.append(event)
            }
        }
        await monitor.emit(.error(.notConnected))
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .error = $0 { return true }
            return false
        }
        #expect(found)
    }

    @Test("markConnected emits nothing by itself")
    func markConnectedEmitsNothing() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        let collector = MonitorEventCollector()
        let task = Task {
            for await event in monitor.events {
                await collector.append(event)
            }
        }
        await monitor.markConnected()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        let nonStats = events.filter {
            if case .statistics = $0 { return false }
            return true
        }
        #expect(nonStats.isEmpty)
    }
}

@Suite("ConnectionMonitor — Periodic Statistics")
struct ConnectionMonitorPeriodicTests {

    @Test("Periodic statistics events emitted while connected")
    func periodicStatsEmittedWhileConnected() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: 0.05)
        let collector = MonitorEventCollector()
        let task = Task {
            for await event in monitor.events {
                await collector.append(event)
            }
        }
        await monitor.markConnected()
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let events = await collector.events
        let statsEvents = events.filter {
            if case .statistics = $0 { return true }
            return false
        }
        #expect(statsEvents.count >= 1)
    }

    @Test("No periodic events when disconnected")
    func noPeriodicEventsWhenDisconnected() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: 0.05)
        let collector = MonitorEventCollector()
        let task = Task {
            for await event in monitor.events {
                await collector.append(event)
            }
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let events = await collector.events
        let statsEvents = events.filter {
            if case .statistics = $0 { return true }
            return false
        }
        #expect(statsEvents.isEmpty)
    }

    @Test("markDisconnected stops periodic emission")
    func markDisconnectedStopsPeriodicEmission() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: 0.05)
        let collector = MonitorEventCollector()
        let task = Task {
            for await event in monitor.events {
                await collector.append(event)
            }
        }
        await monitor.markConnected()
        try await Task.sleep(nanoseconds: 120_000_000)
        await monitor.markDisconnected()
        let countBefore = await collector.events.count
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let countAfter = await collector.events.count
        #expect(countAfter - countBefore <= 1)
    }

    @Test("statisticsInterval nil disables periodic emission")
    func statisticsIntervalNilDisablesEmission() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        let collector = MonitorEventCollector()
        let task = Task {
            for await event in monitor.events {
                await collector.append(event)
            }
        }
        await monitor.markConnected()
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let events = await collector.events
        let statsEvents = events.filter {
            if case .statistics = $0 { return true }
            return false
        }
        #expect(statsEvents.isEmpty)
    }

    @Test("Periodic events contain accurate current statistics")
    func periodicEventsContainAccurateStats() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: 0.05)
        let collector = MonitorEventCollector()
        let task = Task {
            for await event in monitor.events {
                await collector.append(event)
            }
        }
        await monitor.markConnected()
        await monitor.recordBytesSent(1000)
        await monitor.recordMetadataUpdate()
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let events = await collector.events
        let statsEvents = events.compactMap { event -> ConnectionStatistics? in
            if case .statistics(let stats) = event { return stats }
            return nil
        }
        #expect(!statsEvents.isEmpty)
        if let stats = statsEvents.first {
            #expect(stats.bytesSent == 1000)
            #expect(stats.metadataUpdateCount == 1)
        }
    }
}

@Suite("ConnectionMonitor — Edge Cases")
struct ConnectionMonitorEdgeCaseTests {

    @Test("recordBytesSent with zero is a no-op")
    func recordBytesSentZeroIsNoOp() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordBytesSent(0)
        let stats = await monitor.statistics
        #expect(stats.bytesSent == 0)
    }

    @Test("Very large byte counts handled correctly")
    func veryLargeByteCountsHandled() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordBytesSent(1_000_000_000)
        await monitor.recordBytesSent(1_000_000_000)
        let stats = await monitor.statistics
        #expect(stats.bytesSent == 2_000_000_000)
    }

    @Test("Rapid successive recordBytesSent calls")
    func rapidSuccessiveRecordBytesSent() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        for _ in 0..<100 {
            await monitor.recordBytesSent(10)
        }
        let stats = await monitor.statistics
        #expect(stats.bytesSent == 1000)
    }

    @Test("emit before consumer iterates stream is buffered")
    func emitBeforeConsumerIsBuffered() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.emit(.error(.notConnected))
        let collector = MonitorEventCollector()
        let task = Task {
            for await event in monitor.events {
                await collector.append(event)
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .error = $0 { return true }
            return false
        }
        #expect(found)
    }
}
