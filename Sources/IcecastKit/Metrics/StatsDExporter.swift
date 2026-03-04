// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Transport protocol for sending StatsD datagrams.
protocol StatsDSender: Sendable {

    /// Sends a UDP datagram. Errors are silenced (fire-and-forget).
    func send(_ data: Data) async
}

/// StatsD UDP push exporter.
///
/// Sends metrics via UDP to a StatsD-compatible daemon
/// (Telegraf, Graphite, DataDog Agent, etc.).
/// Errors are silenced — StatsD is best-effort by design.
///
/// Usage:
/// ```swift
/// let exporter = StatsDExporter(host: "statsd.local", port: 8125)
/// await client.setMetricsExporter(exporter)
/// ```
public actor StatsDExporter: IcecastMetricsExporter {

    private let prefix: String
    private let sender: any StatsDSender
    private var peakBitrate: Double = 0

    /// Creates a StatsD exporter that sends UDP datagrams.
    ///
    /// - Parameters:
    ///   - host: StatsD daemon hostname. Defaults to `"127.0.0.1"`.
    ///   - port: StatsD daemon port. Defaults to `8125`.
    ///   - prefix: Metric name prefix. Defaults to `"icecast"`.
    public init(
        host: String = "127.0.0.1",
        port: Int = 8125,
        prefix: String = "icecast"
    ) {
        self.prefix = prefix
        self.sender = UDPStatsDSender(host: host, port: port)
    }

    /// Creates a StatsD exporter with an injectable sender (for testing).
    init(prefix: String, sender: any StatsDSender) {
        self.prefix = prefix
        self.sender = sender
    }

    public func export(
        _ statistics: ConnectionStatistics,
        labels: [String: String]
    ) async {
        peakBitrate = max(peakBitrate, statistics.currentBitrate)
        let quality = ConnectionQuality.from(statistics: statistics)

        let lines = [
            "\(prefix).bytes_sent_total:\(statistics.bytesSent)|c",
            "\(prefix).stream_duration_seconds:\(formatFloat(statistics.duration))|c",
            "\(prefix).current_bitrate_bps:\(formatFloat(statistics.currentBitrate))|g",
            "\(prefix).peak_bitrate_bps:\(formatFloat(peakBitrate))|g",
            "\(prefix).metadata_updates_total:\(statistics.metadataUpdateCount)|c",
            "\(prefix).reconnections_total:\(statistics.reconnectionCount)|c",
            "\(prefix).connection_quality_score:\(formatFloat(quality.score))|g",
            "\(prefix).write_latency_ms:\(formatFloat(statistics.averageWriteLatency))|g"
        ]

        let payload = Data(lines.joined(separator: "\n").utf8)
        await sender.send(payload)
    }

    /// StatsD is fire-and-forget — flush is a no-op.
    public func flush() async {}

    // MARK: - Private

    private func formatFloat(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(value)
    }
}

// MARK: - UDP Sender

/// POSIX UDP sender for StatsD datagrams.
struct UDPStatsDSender: StatsDSender {

    private let socketFD: Int32
    private let address: sockaddr_in

    init(host: String, port: Int) {
        #if canImport(Glibc)
            socketFD = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
        #else
            socketFD = socket(AF_INET, SOCK_DGRAM, 0)
        #endif

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(clamping: port).bigEndian
        _ = host.withCString { cstr in
            inet_pton(AF_INET, cstr, &addr.sin_addr)
        }
        address = addr
    }

    func send(_ data: Data) async {
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var addr = address
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(
                    to: sockaddr.self, capacity: 1
                ) { sockPtr in
                    _ = sendto(
                        socketFD, baseAddress, buffer.count, 0,
                        sockPtr,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
    }
}
