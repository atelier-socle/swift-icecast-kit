# Metrics Export

Export streaming metrics to Prometheus, StatsD, or custom monitoring systems.

@Metadata {
    @PageKind(article)
}

## Overview

IcecastKit provides a protocol-based metrics export system with built-in support for Prometheus (OpenMetrics format) and StatsD (UDP datagrams). Metrics are exported periodically with automatic labels for mountpoint and server.

### Exporter Protocol

``IcecastMetricsExporter`` defines the interface for all exporters:

```swift
public protocol IcecastMetricsExporter: Actor {
    func export(_ statistics: ConnectionStatistics, labels: [String: String]) async
    func flush() async
}
```

The protocol uses a generic constraint (not an existential) for type safety. Any actor conforming to this protocol can be used as an exporter.

### Exported Metrics

Both built-in exporters emit 8 metrics:

| Metric | Type | Description |
|--------|------|-------------|
| `icecast_bytes_sent` | counter | Total audio bytes sent |
| `icecast_stream_duration_seconds` | gauge | Streaming duration |
| `icecast_current_bitrate` | gauge | Current bitrate (bps) |
| `icecast_metadata_updates_total` | counter | Metadata update count |
| `icecast_reconnections_total` | counter | Reconnection count |
| `icecast_write_latency_ms` | gauge | Average write latency |
| `icecast_peak_bitrate` | gauge | Peak bitrate observed |
| `icecast_connection_quality_score` | gauge | Quality score (0.0–1.0) |

### Prometheus Exporter

``PrometheusExporter`` renders metrics in OpenMetrics format with `# HELP` and `# TYPE` annotations:

```swift
let exporter = PrometheusExporter { output in
    // Called on each render with the OpenMetrics text
    print(output)
}
let stats = ConnectionStatistics(
    bytesSent: 100_000,
    bytesTotal: 100_000,
    duration: 60.0,
    averageBitrate: 128_000,
    currentBitrate: 128_000,
    averageWriteLatency: 5.0
)
let output = await exporter.render(stats, labels: ["mountpoint": "/live.mp3"])
```

Output format:

```
# HELP icecast_bytes_sent Total audio bytes sent
# TYPE icecast_bytes_sent counter
icecast_bytes_sent{mountpoint="/live.mp3"} 100000
# HELP icecast_current_bitrate Current streaming bitrate in bps
# TYPE icecast_current_bitrate gauge
icecast_current_bitrate{mountpoint="/live.mp3"} 128000.0
```

Labels with special characters are escaped:

```swift
let output = await exporter.render(stats, labels: ["name": "Radio \"Best\""])
// name="Radio \"Best\""
```

**Integration with Vapor** — serve the `/metrics` endpoint:

```swift
let exporter = PrometheusExporter { output in
    // Store for HTTP handler
}

app.get("metrics") { req -> Response in
    let stats = await client.statistics
    let output = await exporter.render(
        stats, labels: ["mountpoint": "/live.mp3"]
    )
    return Response(
        status: .ok,
        headers: ["Content-Type": "text/plain; version=0.0.4"],
        body: .init(string: output)
    )
}
```

### StatsD Exporter

``StatsDExporter`` sends metrics as UDP datagrams in StatsD format:

```swift
let exporter = StatsDExporter(
    host: "127.0.0.1",
    port: 8125,
    prefix: "radio"
)
```

Datagram format uses `|g` for gauges and `|c` for counters:

```
radio.bytes_sent:100000|c
radio.current_bitrate:128000|g
radio.write_latency_ms:5.0|g
```

The StatsD exporter uses POSIX UDP sockets with fire-and-forget semantics — no acknowledgment is expected.

### Attaching to IcecastClient

``IcecastClient/setMetricsExporter(_:interval:labels:)`` starts periodic export:

```swift
let exporter = PrometheusExporter { output in
    // Handle rendered output
}

try await client.connect()
await client.setMetricsExporter(exporter, interval: 10.0)
```

The client automatically generates labels:

| Label | Source |
|-------|--------|
| `mountpoint` | From configuration |
| `server` | From configuration host |

Custom labels override auto-generated ones:

```swift
await client.setMetricsExporter(
    exporter, interval: 10.0,
    labels: ["mountpoint": "custom-label", "env": "production"]
)
```

On ``IcecastClient/disconnect()``, the exporter's ``IcecastMetricsExporter/flush()`` method is called automatically.

### Multi-Client Metrics

``MultiIcecastClient`` supports metrics export with automatic per-destination labels:

```swift
let multi = MultiIcecastClient()
// ... add destinations ...

let exporter = PrometheusExporter { output in print(output) }
await multi.setMetricsExporter(exporter, interval: 10.0)
```

Each destination's metrics are exported with its label as an additional dimension.

### Custom Exporters

Implement ``IcecastMetricsExporter`` to build a custom exporter:

```swift
actor MyExporter: IcecastMetricsExporter {
    func export(
        _ statistics: ConnectionStatistics,
        labels: [String: String]
    ) async {
        // Send to your monitoring system
    }

    func flush() async {
        // Final flush on disconnect
    }
}

let exporter = MyExporter()
await client.setMetricsExporter(exporter, interval: 5.0)
```

## Next Steps

- <doc:ConnectionQualityGuide> — Quality scoring that feeds into metrics
- <doc:MultiDestinationGuide> — Multi-destination metrics with auto-labels
- <doc:MonitoringGuide> — Real-time events and statistics
