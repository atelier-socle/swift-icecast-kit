// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - Mock Sender

/// Captures sent data for testing StatsDExporter without real UDP.
actor MockStatsDSender: StatsDSender {
    private(set) var sentData: [Data] = []

    func send(_ data: Data) async {
        sentData.append(data)
    }

    var lastPayload: String? {
        guard let data = sentData.last else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var payloadCount: Int { sentData.count }
}

// MARK: - StatsD Format Tests

@Suite("StatsDExporter — Datagram Format")
struct StatsDFormatTests {

    private func makeStats(
        bytesSent: UInt64 = 1_234_567,
        duration: TimeInterval = 3600.5,
        currentBitrate: Double = 128_000,
        metadataUpdateCount: Int = 42,
        reconnectionCount: Int = 2,
        averageWriteLatency: Double = 12.5
    ) -> ConnectionStatistics {
        ConnectionStatistics(
            bytesSent: bytesSent,
            duration: duration,
            currentBitrate: currentBitrate,
            metadataUpdateCount: metadataUpdateCount,
            reconnectionCount: reconnectionCount,
            averageWriteLatency: averageWriteLatency
        )
    }

    @Test("Datagram format is prefix.metric_name:value|type")
    func datagramFormatCorrect() async {
        let sender = MockStatsDSender()
        let exporter = StatsDExporter(prefix: "icecast", sender: sender)
        await exporter.export(makeStats(), labels: [:])

        let payload = await sender.lastPayload
        #expect(payload != nil)
        #expect(payload?.contains("icecast.bytes_sent_total:1234567|c") == true)
    }

    @Test("Counter metrics use |c type")
    func counterMetricsUseC() async {
        let sender = MockStatsDSender()
        let exporter = StatsDExporter(prefix: "icecast", sender: sender)
        await exporter.export(makeStats(), labels: [:])

        let payload = await sender.lastPayload ?? ""
        let lines = payload.split(separator: "\n")

        let counterMetrics = [
            "icecast.bytes_sent_total",
            "icecast.stream_duration_seconds",
            "icecast.metadata_updates_total",
            "icecast.reconnections_total"
        ]
        for metric in counterMetrics {
            let line = lines.first { $0.hasPrefix(metric) }
            #expect(line?.hasSuffix("|c") == true, "Expected counter type for \(metric)")
        }
    }

    @Test("Gauge metrics use |g type")
    func gaugeMetricsUseG() async {
        let sender = MockStatsDSender()
        let exporter = StatsDExporter(prefix: "icecast", sender: sender)
        await exporter.export(makeStats(), labels: [:])

        let payload = await sender.lastPayload ?? ""
        let lines = payload.split(separator: "\n")

        let gaugeMetrics = [
            "icecast.current_bitrate_bps",
            "icecast.peak_bitrate_bps",
            "icecast.connection_quality_score",
            "icecast.write_latency_ms"
        ]
        for metric in gaugeMetrics {
            let line = lines.first { $0.hasPrefix(metric) }
            #expect(line?.hasSuffix("|g") == true, "Expected gauge type for \(metric)")
        }
    }

    @Test("Custom prefix is used")
    func customPrefixUsed() async {
        let sender = MockStatsDSender()
        let exporter = StatsDExporter(prefix: "radio", sender: sender)
        await exporter.export(makeStats(), labels: [:])

        let payload = await sender.lastPayload ?? ""
        #expect(payload.contains("radio.bytes_sent_total"))
        #expect(!payload.contains("icecast.bytes_sent_total"))
    }

    @Test("All 8 metrics are included in payload")
    func allMetricsIncluded() async {
        let sender = MockStatsDSender()
        let exporter = StatsDExporter(prefix: "icecast", sender: sender)
        await exporter.export(makeStats(), labels: [:])

        let payload = await sender.lastPayload ?? ""
        let lines = payload.split(separator: "\n")
        #expect(lines.count == 8)
    }

    @Test("export() does not throw (fire-and-forget)")
    func exportDoesNotThrow() async {
        let sender = MockStatsDSender()
        let exporter = StatsDExporter(prefix: "icecast", sender: sender)
        await exporter.export(makeStats(), labels: [:])

        let count = await sender.payloadCount
        #expect(count == 1)
    }

    @Test("flush() is a no-op")
    func flushIsNoOp() async {
        let sender = MockStatsDSender()
        let exporter = StatsDExporter(prefix: "icecast", sender: sender)
        await exporter.flush()

        let count = await sender.payloadCount
        #expect(count == 0)
    }

    @Test("Peak bitrate tracks highest value across exports")
    func peakBitrateTracksHighest() async {
        let sender = MockStatsDSender()
        let exporter = StatsDExporter(prefix: "icecast", sender: sender)

        await exporter.export(
            ConnectionStatistics(currentBitrate: 100_000), labels: [:]
        )
        var payload = await sender.lastPayload ?? ""
        #expect(payload.contains("icecast.peak_bitrate_bps:100000|g"))

        await exporter.export(
            ConnectionStatistics(currentBitrate: 80_000), labels: [:]
        )
        payload = await sender.lastPayload ?? ""
        #expect(payload.contains("icecast.peak_bitrate_bps:100000|g"))
    }

    @Test("Public init creates exporter without error")
    func publicInitCreatesExporter() async {
        let exporter = StatsDExporter(
            host: "127.0.0.1", port: 8125, prefix: "test"
        )
        // Fire-and-forget: export to localhost (no daemon needed)
        await exporter.export(ConnectionStatistics(), labels: [:])
        await exporter.flush()
    }

    @Test("Float values use decimal point for fractional numbers")
    func floatValuesDecimalPoint() async {
        let sender = MockStatsDSender()
        let exporter = StatsDExporter(prefix: "icecast", sender: sender)
        await exporter.export(
            ConnectionStatistics(
                duration: 3600.5, averageWriteLatency: 12.5
            ),
            labels: [:]
        )

        let payload = await sender.lastPayload ?? ""
        #expect(payload.contains("3600.5|c"))
        #expect(payload.contains("12.5|g"))
    }
}
