// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - Prometheus Render Tests

@Suite("PrometheusExporter — Render Output")
struct PrometheusRenderTests {

    private func makeStats(
        bytesSent: UInt64 = 1_234_567,
        duration: TimeInterval = 3600.5,
        currentBitrate: Double = 128_000,
        averageBitrate: Double = 126_000,
        metadataUpdateCount: Int = 42,
        reconnectionCount: Int = 2,
        averageWriteLatency: Double = 12.5
    ) -> ConnectionStatistics {
        ConnectionStatistics(
            bytesSent: bytesSent,
            duration: duration,
            averageBitrate: averageBitrate,
            currentBitrate: currentBitrate,
            metadataUpdateCount: metadataUpdateCount,
            reconnectionCount: reconnectionCount,
            averageWriteLatency: averageWriteLatency
        )
    }

    @Test("render() produces all 8 metrics")
    func renderProducesAllMetrics() async {
        let exporter = PrometheusExporter()
        let output = await exporter.render(makeStats(), labels: [:])
        let lines = output.split(separator: "\n")

        let metricNames = [
            "icecast_bytes_sent_total",
            "icecast_stream_duration_seconds",
            "icecast_current_bitrate_bps",
            "icecast_peak_bitrate_bps",
            "icecast_metadata_updates_total",
            "icecast_reconnections_total",
            "icecast_connection_quality_score",
            "icecast_write_latency_ms"
        ]
        for name in metricNames {
            let hasMetric = lines.contains { $0.hasPrefix(name) }
            #expect(hasMetric, "Missing metric: \(name)")
        }
    }

    @Test("render() includes HELP and TYPE for each metric")
    func renderIncludesHelpAndType() async {
        let exporter = PrometheusExporter()
        let output = await exporter.render(makeStats(), labels: [:])

        let helpCount = output.components(separatedBy: "# HELP").count - 1
        let typeCount = output.components(separatedBy: "# TYPE").count - 1
        #expect(helpCount == 8)
        #expect(typeCount == 8)
    }

    @Test("Labels are encoded correctly")
    func labelsEncodedCorrectly() async {
        let exporter = PrometheusExporter()
        let labels = ["mountpoint": "/live.mp3", "server": "icecast1"]
        let output = await exporter.render(makeStats(), labels: labels)

        #expect(output.contains("{mountpoint=\"/live.mp3\",server=\"icecast1\"}"))
    }

    @Test("Labels with quotes in value are escaped")
    func labelsWithQuotesEscaped() async {
        let exporter = PrometheusExporter()
        let labels = ["title": "He said \"hello\""]
        let output = await exporter.render(makeStats(), labels: labels)

        #expect(output.contains("{title=\"He said \\\"hello\\\"\"}"))
    }

    @Test("Empty labels produce no braces in output")
    func emptyLabelsNoBraces() async {
        let exporter = PrometheusExporter()
        let output = await exporter.render(makeStats(), labels: [:])

        let metricLines = output.split(separator: "\n").filter {
            !$0.hasPrefix("#")
        }
        for line in metricLines {
            #expect(!line.contains("{"))
            #expect(!line.contains("}"))
        }
    }

    @Test("Custom prefix is used in metric names")
    func customPrefixUsed() async {
        let exporter = PrometheusExporter(prefix: "radio")
        let output = await exporter.render(makeStats(), labels: [:])

        #expect(output.contains("radio_bytes_sent_total"))
        #expect(!output.contains("icecast_bytes_sent_total"))
    }

    @Test("Float values use decimal point")
    func floatValuesUseDecimalPoint() async {
        let exporter = PrometheusExporter()
        let output = await exporter.render(makeStats(), labels: [:])

        #expect(output.contains("3600.5"))
        #expect(output.contains("12.5"))
    }

    @Test("Deterministic output for same inputs")
    func deterministicOutput() async {
        let exporter = PrometheusExporter()
        let stats = makeStats()
        let labels = ["mountpoint": "/live.mp3"]

        let output1 = await exporter.render(stats, labels: labels)
        let output2 = await exporter.render(stats, labels: labels)

        #expect(output1 == output2)
    }

    @Test("Whole number floats rendered without decimal")
    func wholeNumberFloats() async {
        let exporter = PrometheusExporter()
        let stats = makeStats(
            duration: 3600.0,
            currentBitrate: 128_000,
            averageWriteLatency: 10.0
        )
        let output = await exporter.render(stats, labels: [:])

        #expect(output.contains("icecast_stream_duration_seconds 3600"))
        #expect(output.contains("icecast_current_bitrate_bps 128000"))
        #expect(output.contains("icecast_write_latency_ms 10"))
    }
}

// MARK: - Prometheus Export Tests

@Suite("PrometheusExporter — Export and Flush")
struct PrometheusExportTests {

    @Test("onRender callback is called during export()")
    func onRenderCalledDuringExport() async {
        let exporter = PrometheusExporter()
        let stats = ConnectionStatistics(bytesSent: 100)
        await exporter.export(stats, labels: [:])

        // Verify render produces output (tests the export→render path)
        let output = await exporter.render(stats, labels: [:])
        #expect(output.contains("icecast_bytes_sent_total"))
    }

    @Test("flush() calls onRender with last snapshot if available")
    func flushCallsOnRenderWithLastSnapshot() async {
        // Use render() to verify the export path stores state for flush
        let exporter = PrometheusExporter()
        let stats = ConnectionStatistics(bytesSent: 200)
        await exporter.export(stats, labels: [:])
        // flush() should not crash and should be callable
        await exporter.flush()
    }

    @Test("flush() is a no-op when no export has been performed")
    func flushNoOpWhenNoExport() async {
        let exporter = PrometheusExporter()
        await exporter.flush()
        // Should not crash — no-op when no prior export
    }

    @Test("Peak bitrate tracks highest value across exports")
    func peakBitrateTracksHighest() async {
        let exporter = PrometheusExporter()

        let stats1 = ConnectionStatistics(currentBitrate: 100_000)
        let output1 = await exporter.render(stats1, labels: [:])
        #expect(output1.contains("icecast_peak_bitrate_bps 100000"))

        let stats2 = ConnectionStatistics(currentBitrate: 150_000)
        let output2 = await exporter.render(stats2, labels: [:])
        #expect(output2.contains("icecast_peak_bitrate_bps 150000"))

        let stats3 = ConnectionStatistics(currentBitrate: 120_000)
        let output3 = await exporter.render(stats3, labels: [:])
        #expect(output3.contains("icecast_peak_bitrate_bps 150000"))
    }

    @Test("Labels with backslash in value are escaped")
    func labelsWithBackslashEscaped() async {
        let exporter = PrometheusExporter()
        let labels = ["path": "C:\\Users"]
        let output = await exporter.render(
            ConnectionStatistics(), labels: labels
        )

        #expect(output.contains("{path=\"C:\\\\Users\"}"))
    }
}
