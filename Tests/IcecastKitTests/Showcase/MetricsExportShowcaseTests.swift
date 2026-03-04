// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

/// Mock exporter for showcase tests.
private actor ShowcaseMockExporter: IcecastMetricsExporter {
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

    func waitForExport() async {
        await withCheckedContinuation { continuation in
            exportContinuations.append(continuation)
        }
    }

    var exportCallCount: Int { exportCalls.count }
    var lastLabels: [String: String]? { exportCalls.last?.1 }
}

@Suite("Showcase — Metrics Export")
struct MetricsExportShowcaseTests {

    private static let putOKResponse = Data(
        "HTTP/1.1 200 OK\r\nServer: Icecast 2.4.4\r\n\r\n".utf8
    )

    private func makeStats(
        bytesSent: UInt64 = 100_000,
        duration: TimeInterval = 60.0,
        currentBitrate: Double = 128_000,
        metadataUpdateCount: Int = 2,
        reconnectionCount: Int = 0,
        averageWriteLatency: Double = 5.0
    ) -> ConnectionStatistics {
        ConnectionStatistics(
            bytesSent: bytesSent,
            bytesTotal: bytesSent,
            duration: duration,
            averageBitrate: currentBitrate,
            currentBitrate: currentBitrate,
            metadataUpdateCount: metadataUpdateCount,
            reconnectionCount: reconnectionCount,
            averageWriteLatency: averageWriteLatency
        )
    }

    // MARK: - Showcase 1: Prometheus contains all 8 metrics

    @Test("Prometheus render contains all 8 metrics")
    func prometheusRenderContainsAllMetrics() async {
        let exporter = PrometheusExporter { _ in }
        let stats = makeStats()
        let labels = ["mountpoint": "/live.mp3"]
        let output = await exporter.render(stats, labels: labels)

        #expect(output.contains("icecast_bytes_sent"))
        #expect(output.contains("icecast_stream_duration_seconds"))
        #expect(output.contains("icecast_current_bitrate"))
        #expect(output.contains("icecast_metadata_updates_total"))
        #expect(output.contains("icecast_reconnections_total"))
        #expect(output.contains("icecast_write_latency_ms"))
        #expect(output.contains("icecast_peak_bitrate"))
        #expect(output.contains("icecast_connection_quality_score"))
    }

    // MARK: - Showcase 2: Prometheus HELP and TYPE lines

    @Test("Prometheus format includes # HELP and # TYPE lines")
    func prometheusFormatHasHelpAndTypeLines() async {
        let exporter = PrometheusExporter { _ in }
        let stats = makeStats()
        let output = await exporter.render(stats, labels: [:])

        #expect(output.contains("# HELP"))
        #expect(output.contains("# TYPE"))
        #expect(output.contains("gauge") || output.contains("counter"))
    }

    // MARK: - Showcase 3: Prometheus labels encoded

    @Test("Prometheus labels encoded correctly")
    func prometheusLabelsEncodedCorrectly() async {
        let exporter = PrometheusExporter { _ in }
        let stats = makeStats()
        let labels = ["mountpoint": "/live.mp3", "server": "radio1"]
        let output = await exporter.render(stats, labels: labels)
        #expect(output.contains("mountpoint=\"/live.mp3\""))
        #expect(output.contains("server=\"radio1\""))
    }

    // MARK: - Showcase 4: Prometheus escapes quotes in labels

    @Test("Prometheus escapes quotes in label values")
    func prometheusLabelQuotesEscaped() async {
        let exporter = PrometheusExporter { _ in }
        let stats = makeStats()
        let labels = ["name": "Radio \"Best\""]
        let output = await exporter.render(stats, labels: labels)
        #expect(output.contains("Radio \\\"Best\\\""))
    }

    // MARK: - Showcase 5: Prometheus onRender callback

    @Test("Prometheus onRender callback called on render")
    func prometheusOnRenderCalledOnExport() async {
        let stream = AsyncStream.makeStream(of: String.self)
        let exporter = PrometheusExporter { output in
            stream.continuation.yield(output)
        }
        let stats = makeStats()
        await exporter.export(stats, labels: [:])
        stream.continuation.finish()
        var receivedCount = 0
        for await _ in stream.stream {
            receivedCount += 1
        }
        #expect(receivedCount >= 1)
    }

    // MARK: - Showcase 6: StatsD datagram format

    @Test("StatsD datagrams have correct format with prefix")
    func statsDDatagramsHaveCorrectFormat() async {
        let sender = MockShowcaseStatsDSender()
        let exporter = StatsDExporter(prefix: "radio", sender: sender)
        await exporter.export(makeStats(), labels: [:])
        await exporter.flush()

        let payload = await sender.lastPayload
        #expect(payload?.contains("radio.") == true)
    }

    // MARK: - Showcase 7: StatsD metric types

    @Test("StatsD uses |g for gauges and |c for counters")
    func statsDMetricTypesAreCorrect() async {
        let sender = MockShowcaseStatsDSender()
        let exporter = StatsDExporter(prefix: "icecast", sender: sender)
        await exporter.export(makeStats(), labels: [:])
        await exporter.flush()

        let payload = await sender.lastPayload ?? ""
        #expect(payload.contains("|g") || payload.contains("|c"))
    }

    // MARK: - Showcase 8: Client metrics timer triggers export

    @Test("IcecastClient metrics timer triggers periodic export")
    func clientMetricsTimerTriggersPeriodicExport() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let client = IcecastClient(
            configuration: IcecastConfiguration(
                host: "radio.example.com",
                mountpoint: "/live.mp3"
            ),
            credentials: IcecastCredentials(password: "hackme"),
            connectionFactory: { mock }
        )

        let exporter = ShowcaseMockExporter()
        try await client.connect()
        await client.setMetricsExporter(exporter, interval: 0.1)
        await exporter.waitForExport()

        let callCount = await exporter.exportCallCount
        #expect(callCount >= 1)
        await client.disconnect()
    }

    // MARK: - Showcase 9: Client flushes metrics on disconnect

    @Test("IcecastClient flushes metrics exporter on disconnect")
    func clientFlushesMetricsOnDisconnect() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let client = IcecastClient(
            configuration: IcecastConfiguration(
                host: "radio.example.com",
                mountpoint: "/live.mp3"
            ),
            credentials: IcecastCredentials(password: "hackme"),
            connectionFactory: { mock }
        )

        let exporter = ShowcaseMockExporter()
        try await client.connect()
        await client.setMetricsExporter(exporter, interval: 0.1)
        await exporter.waitForExport()

        await client.disconnect()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let flushCount = await exporter.flushCallCount
        #expect(flushCount >= 1)
    }

    // MARK: - Showcase 10: Auto-labels include mountpoint and server

    @Test("Auto-labels contain mountpoint and server")
    func autoLabelsContainMountpointAndServer() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let client = IcecastClient(
            configuration: IcecastConfiguration(
                host: "radio.example.com",
                mountpoint: "/live.mp3"
            ),
            credentials: IcecastCredentials(password: "hackme"),
            connectionFactory: { mock }
        )

        let exporter = ShowcaseMockExporter()
        try await client.connect()
        await client.setMetricsExporter(exporter, interval: 0.1)
        await exporter.waitForExport()

        let labels = await exporter.lastLabels ?? [:]
        #expect(labels["mountpoint"] == "/live.mp3")
        #expect(labels["server"] == "radio.example.com")
        await client.disconnect()
    }

    // MARK: - Showcase 11: Consumer labels override auto-labels

    @Test("Consumer labels override auto-generated labels")
    func consumerLabelsOverrideAutoLabels() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let client = IcecastClient(
            configuration: IcecastConfiguration(
                host: "radio.example.com",
                mountpoint: "/live.mp3"
            ),
            credentials: IcecastCredentials(password: "hackme"),
            connectionFactory: { mock }
        )

        let exporter = ShowcaseMockExporter()
        try await client.connect()
        await client.setMetricsExporter(
            exporter, interval: 0.1,
            labels: ["mountpoint": "overridden"]
        )
        await exporter.waitForExport()

        let labels = await exporter.lastLabels ?? [:]
        #expect(labels["mountpoint"] == "overridden")
        await client.disconnect()
    }
}

// MARK: - Mock StatsD Sender

private actor MockShowcaseStatsDSender: StatsDSender {
    private(set) var sentData: [Data] = []

    func send(_ data: Data) async {
        sentData.append(data)
    }

    var lastPayload: String? {
        guard let data = sentData.last else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
