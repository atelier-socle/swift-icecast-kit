// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Pluggable metrics backend protocol.
///
/// Conform to this protocol to implement a custom metrics exporter
/// (e.g., InfluxDB, CloudWatch, custom logging). The two provided
/// implementations are ``PrometheusExporter`` and ``StatsDExporter``.
public protocol IcecastMetricsExporter: Sendable {

    /// Exports a statistics snapshot with associated labels.
    ///
    /// Called periodically by ``IcecastClient`` at the configured interval.
    ///
    /// - Parameters:
    ///   - statistics: The current connection statistics snapshot.
    ///   - labels: Key-value labels (e.g., mountpoint, server name).
    func export(
        _ statistics: ConnectionStatistics,
        labels: [String: String]
    ) async

    /// Flushes any buffered metrics.
    ///
    /// Called on disconnect or when the exporter is detached.
    func flush() async
}

/// Configuration for periodic metrics export from ``IcecastClient``.
///
/// Usage:
/// ```swift
/// let prometheus = PrometheusExporter()
/// let config = MetricsExportConfiguration(
///     exporter: prometheus,
///     interval: 15.0,
///     labels: ["env": "production"]
/// )
/// ```
public struct MetricsExportConfiguration<Exporter: IcecastMetricsExporter>:
    Sendable
{

    /// The metrics exporter to use.
    public var exporter: Exporter

    /// How often to export metrics in seconds. Minimum: 1.0.
    public var interval: TimeInterval

    /// Labels to attach to all exported metrics.
    ///
    /// If empty, ``IcecastClient`` auto-populates with mountpoint and host.
    /// Consumer-provided labels override auto-populated ones.
    public var labels: [String: String]

    /// Creates a metrics export configuration.
    ///
    /// - Parameters:
    ///   - exporter: The metrics exporter to use.
    ///   - interval: Export interval in seconds. Clamped to minimum 1.0.
    ///   - labels: Labels to attach to exported metrics. Defaults to empty.
    public init(
        exporter: Exporter,
        interval: TimeInterval = 10.0,
        labels: [String: String] = [:]
    ) {
        self.exporter = exporter
        self.interval = max(1.0, interval)
        self.labels = labels
    }
}
