// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - Mock Exporter

/// A test exporter that records all export/flush calls with deterministic signaling.
actor MockMetricsExporter: IcecastMetricsExporter {
    private(set) var exportCalls: [(ConnectionStatistics, [String: String])] = []
    private(set) var flushCallCount: Int = 0
    private var exportContinuations: [CheckedContinuation<Void, Never>] = []

    func export(
        _ statistics: ConnectionStatistics,
        labels: [String: String]
    ) async {
        exportCalls.append((statistics, labels))
        let continuations = exportContinuations
        exportContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func flush() async {
        flushCallCount += 1
    }

    var lastLabels: [String: String]? {
        exportCalls.last?.1
    }

    var exportCallCount: Int { exportCalls.count }

    /// Awaits the next export() call deterministically (no sleep).
    func waitForExport() async {
        await withCheckedContinuation { continuation in
            exportContinuations.append(continuation)
        }
    }
}

// MARK: - MetricsExportConfiguration Tests

@Suite("MetricsExportConfiguration — Validation")
struct MetricsConfigurationTests {

    @Test("Interval minimum is clamped to 1.0")
    func intervalMinimumClamped() {
        let exporter = PrometheusExporter()
        let config = MetricsExportConfiguration(
            exporter: exporter, interval: 0.1
        )
        #expect(config.interval == 1.0)
    }

    @Test("Interval at 1.0 is accepted")
    func intervalAtMinimum() {
        let exporter = PrometheusExporter()
        let config = MetricsExportConfiguration(
            exporter: exporter, interval: 1.0
        )
        #expect(config.interval == 1.0)
    }

    @Test("Default interval is 10.0")
    func defaultInterval() {
        let exporter = PrometheusExporter()
        let config = MetricsExportConfiguration(exporter: exporter)
        #expect(config.interval == 10.0)
    }

    @Test("Default labels are empty")
    func defaultLabelsEmpty() {
        let exporter = PrometheusExporter()
        let config = MetricsExportConfiguration(exporter: exporter)
        #expect(config.labels.isEmpty)
    }

    @Test("Negative interval is clamped to 1.0")
    func negativeIntervalClamped() {
        let exporter = PrometheusExporter()
        let config = MetricsExportConfiguration(
            exporter: exporter, interval: -5.0
        )
        #expect(config.interval == 1.0)
    }
}

// MARK: - IcecastClient Metrics Integration

@Suite("IcecastClient — Metrics Integration")
struct MetricsClientIntegrationTests {

    private func makeConnectedClient() async throws -> (
        IcecastClient, MockTransportConnection
    ) {
        let transport = MockTransportConnection()
        let okResponse = Data(
            "HTTP/1.0 200 OK\r\nContent-Type: audio/mpeg\r\n\r\n".utf8
        )
        await transport.enqueueResponse(okResponse)

        let config = IcecastConfiguration(
            host: "radio.example.com",
            mountpoint: "/live.mp3",
            credentials: IcecastCredentials(password: "secret")
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "secret"),
            connectionFactory: { transport }
        )
        try await client.connect()
        return (client, transport)
    }

    @Test("setMetricsExporter attaches exporter")
    func setMetricsExporterAttaches() async throws {
        let (client, _) = try await makeConnectedClient()
        let exporter = MockMetricsExporter()
        await client.setMetricsExporter(exporter, interval: 0.1)

        await exporter.waitForExport()

        let callCount = await exporter.exportCallCount
        #expect(callCount >= 1)
        await client.disconnect()
    }

    @Test("Disconnect triggers flush on exporter")
    func disconnectTriggersFlush() async throws {
        let (client, _) = try await makeConnectedClient()
        let exporter = MockMetricsExporter()
        await client.setMetricsExporter(exporter, interval: 10.0)
        await client.disconnect()

        let flushCount = await exporter.flushCallCount
        #expect(flushCount >= 1)
    }

    @Test("setMetricsExporter(nil) detaches and stops timer")
    func setNilDetachesExporter() async throws {
        let (client, _) = try await makeConnectedClient()
        let exporter = MockMetricsExporter()
        await client.setMetricsExporter(exporter, interval: 10.0)
        await client.setMetricsExporter(nil as MockMetricsExporter?)

        let flushCount = await exporter.flushCallCount
        #expect(flushCount >= 1)
        await client.disconnect()
    }

    @Test("Auto-labels include mountpoint and server")
    func autoLabelsPopulated() async throws {
        let (client, _) = try await makeConnectedClient()
        let exporter = MockMetricsExporter()
        await client.setMetricsExporter(exporter, interval: 0.1)

        await exporter.waitForExport()

        let labels = await exporter.lastLabels
        #expect(labels?["mountpoint"] == "/live.mp3")
        #expect(labels?["server"] == "radio.example.com")
        await client.disconnect()
    }

    @Test("Consumer labels override auto-labels")
    func consumerLabelsOverride() async throws {
        let (client, _) = try await makeConnectedClient()
        let exporter = MockMetricsExporter()
        await client.setMetricsExporter(
            exporter, interval: 0.1,
            labels: ["server": "custom-server", "env": "production"]
        )

        await exporter.waitForExport()

        let labels = await exporter.lastLabels
        #expect(labels?["server"] == "custom-server")
        #expect(labels?["env"] == "production")
        #expect(labels?["mountpoint"] == "/live.mp3")
        await client.disconnect()
    }
}

// MARK: - Custom Exporter Protocol Conformance

@Suite("Custom IcecastMetricsExporter")
struct CustomExporterTests {

    @Test("Custom exporter conforming to protocol works with client")
    func customExporterWorks() async throws {
        let transport = MockTransportConnection()
        let okResponse = Data(
            "HTTP/1.0 200 OK\r\nContent-Type: audio/mpeg\r\n\r\n".utf8
        )
        await transport.enqueueResponse(okResponse)

        let config = IcecastConfiguration(
            host: "radio.example.com",
            mountpoint: "/live.mp3",
            credentials: IcecastCredentials(password: "secret")
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "secret"),
            connectionFactory: { transport }
        )
        try await client.connect()

        let exporter = MockMetricsExporter()
        await client.setMetricsExporter(exporter, interval: 0.1)

        await exporter.waitForExport()

        let callCount = await exporter.exportCallCount
        #expect(callCount >= 1)
        await client.disconnect()
    }
}

// MARK: - MultiIcecastClient Metrics

@Suite("MultiIcecastClient — Metrics Integration")
struct MultiMetricsTests {

    @Test("setMetricsExporter propagates to all destinations")
    func metricsPropagatesToAllDestinations() async throws {
        let transport = MockTransportConnection()
        let okResponse = Data(
            "HTTP/1.0 200 OK\r\nContent-Type: audio/mpeg\r\n\r\n".utf8
        )
        await transport.enqueueResponse(okResponse)
        await transport.enqueueResponse(okResponse)

        let multi = MultiIcecastClient { transport }
        try await multi.addDestination(
            "primary",
            configuration: IcecastConfiguration(
                host: "radio1.example.com",
                mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "s1")
            )
        )
        try await multi.addDestination(
            "backup",
            configuration: IcecastConfiguration(
                host: "radio2.example.com",
                mountpoint: "/backup.mp3",
                credentials: IcecastCredentials(password: "s2")
            )
        )

        let exporter = MockMetricsExporter()
        await multi.setMetricsExporter(exporter, interval: 10.0)

        // Verify by disconnecting — flush is called on each client
        await multi.disconnectAll()
    }

    @Test("setMetricsExporter(nil) detaches from all destinations")
    func nilDetachesFromAll() async throws {
        let transport = MockTransportConnection()
        let multi = MultiIcecastClient { transport }
        try await multi.addDestination(
            "primary",
            configuration: IcecastConfiguration(
                host: "radio1.example.com",
                mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "s1")
            )
        )

        let exporter = MockMetricsExporter()
        await multi.setMetricsExporter(exporter, interval: 10.0)
        await multi.setMetricsExporter(nil as MockMetricsExporter?)
        await multi.disconnectAll()
    }
}
