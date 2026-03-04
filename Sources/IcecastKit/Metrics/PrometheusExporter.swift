// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Prometheus text exposition format exporter (OpenMetrics compatible).
///
/// Generates formatted text output — wire it to your own HTTP `/metrics`
/// endpoint via the ``onRender`` callback.
///
/// Usage:
/// ```swift
/// let exporter = PrometheusExporter { output in
///     // Serve `output` at your /metrics endpoint
/// }
/// await client.setMetricsExporter(exporter)
/// ```
public actor PrometheusExporter: IcecastMetricsExporter {

    private let prefix: String
    private var peakBitrate: Double = 0
    private var lastOutput: String?

    /// Called each time metrics are rendered.
    ///
    /// Use this callback to serve the output at your HTTP `/metrics` endpoint.
    public var onRender: (@Sendable (String) -> Void)?

    /// Creates a Prometheus exporter.
    ///
    /// - Parameters:
    ///   - prefix: Metric name prefix. Defaults to `"icecast"`.
    ///   - onRender: Callback invoked with the rendered text on each export.
    public init(
        prefix: String = "icecast",
        onRender: (@Sendable (String) -> Void)? = nil
    ) {
        self.prefix = prefix
        self.onRender = onRender
    }

    /// Generates Prometheus text format from a statistics snapshot.
    ///
    /// Produces 8 metrics with `# HELP` and `# TYPE` annotations.
    /// Output order is deterministic.
    ///
    /// - Parameters:
    ///   - statistics: The connection statistics to render.
    ///   - labels: Key-value labels for all metrics.
    /// - Returns: The complete Prometheus text exposition output.
    public func render(
        _ statistics: ConnectionStatistics,
        labels: [String: String]
    ) -> String {
        peakBitrate = max(peakBitrate, statistics.currentBitrate)
        let quality = ConnectionQuality.from(statistics: statistics)
        let labelStr = formatLabels(labels)

        let metrics: [MetricEntry] = [
            MetricEntry(
                name: "\(prefix)_bytes_sent_total",
                help: "Total bytes sent to the Icecast server",
                type: "counter",
                value: "\(statistics.bytesSent)"
            ),
            MetricEntry(
                name: "\(prefix)_stream_duration_seconds",
                help: "Total stream duration in seconds",
                type: "counter",
                value: formatFloat(statistics.duration)
            ),
            MetricEntry(
                name: "\(prefix)_current_bitrate_bps",
                help: "Current streaming bitrate in bits per second",
                type: "gauge",
                value: formatFloat(statistics.currentBitrate)
            ),
            MetricEntry(
                name: "\(prefix)_peak_bitrate_bps",
                help: "Peak streaming bitrate in bits per second",
                type: "gauge",
                value: formatFloat(peakBitrate)
            ),
            MetricEntry(
                name: "\(prefix)_metadata_updates_total",
                help: "Total number of metadata updates sent",
                type: "counter",
                value: "\(statistics.metadataUpdateCount)"
            ),
            MetricEntry(
                name: "\(prefix)_reconnections_total",
                help: "Total number of reconnection attempts",
                type: "counter",
                value: "\(statistics.reconnectionCount)"
            ),
            MetricEntry(
                name: "\(prefix)_connection_quality_score",
                help: "Current connection quality score (0.0-1.0)",
                type: "gauge",
                value: formatFloat(quality.score)
            ),
            MetricEntry(
                name: "\(prefix)_write_latency_ms",
                help: "Average write latency in milliseconds",
                type: "gauge",
                value: formatFloat(statistics.averageWriteLatency)
            )
        ]

        var lines: [String] = []
        for metric in metrics {
            lines.append("# HELP \(metric.name) \(metric.help)")
            lines.append("# TYPE \(metric.name) \(metric.type)")
            lines.append("\(metric.name)\(labelStr) \(metric.value)")
        }

        return lines.joined(separator: "\n")
    }

    public func export(
        _ statistics: ConnectionStatistics,
        labels: [String: String]
    ) async {
        let output = render(statistics, labels: labels)
        lastOutput = output
        onRender?(output)
    }

    public func flush() async {
        if let output = lastOutput {
            onRender?(output)
        }
    }

    // MARK: - Private

    private struct MetricEntry {
        let name: String
        let help: String
        let type: String
        let value: String
    }

    private func formatLabels(_ labels: [String: String]) -> String {
        guard !labels.isEmpty else { return "" }
        let sorted = labels.sorted { $0.key < $1.key }
        let pairs = sorted.map { key, value in
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\(key)=\"\(escaped)\""
        }
        return "{\(pairs.joined(separator: ","))}"
    }

    private func formatFloat(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(value)
    }
}
