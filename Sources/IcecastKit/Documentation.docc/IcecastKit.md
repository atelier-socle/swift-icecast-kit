# ``IcecastKit``

@Metadata {
    @DisplayName("IcecastKit")
}

Pure Swift client library for streaming audio to Icecast and SHOUTcast servers.

## Overview

IcecastKit provides a complete, production-ready client for live audio streaming over Icecast and SHOUTcast protocols. The library handles protocol negotiation, authentication, metadata updates, reconnection, and connection monitoring — all built with Swift 6.2 strict concurrency and zero external dependencies.

```swift
import IcecastKit

let client = IcecastClient(
    configuration: IcecastConfiguration(host: "radio.example.com", mountpoint: "/live.mp3"),
    credentials: IcecastCredentials(password: "hackme")
)
try await client.connect()
try await client.send(audioData)
try await client.updateMetadata(ICYMetadata(streamTitle: "Artist - Song"))
await client.disconnect()
```

### Key Features

- **Icecast PUT** — Modern Icecast 2.4+ streaming with HTTP PUT and `Expect: 100-continue`
- **Icecast SOURCE** — Legacy protocol for pre-2.4.0 servers with automatic fallback
- **SHOUTcast v1/v2** — Password authentication, stream IDs, and ICY headers
- **Auto-negotiation** — Automatic protocol detection: tries PUT first, falls back to SOURCE
- **ICY metadata** — Binary wire format encoding/decoding with Unicode support
- **Admin API** — Server-side metadata updates, server stats, and mountpoint stats
- **Auto-reconnect** — Exponential backoff with configurable jitter and retry policies
- **AsyncStream monitoring** — Real-time events, statistics, and bitrate tracking
- **Adaptive bitrate** — EWMA-based congestion detection with configurable policies
- **Multi-destination** — Stream to multiple servers with failure isolation
- **Bandwidth probing** — Pre-stream upload measurement with quality recommendations
- **Connection quality** — Composite score (0.0–1.0) with five weighted metrics
- **Stream recording** — Local recording with size/time-based file rotation
- **Relay / ingest** — Pull audio from existing streams with ICY demuxing
- **Advanced auth** — Digest (RFC 7616), Bearer token, query token, URL-embedded
- **Server presets** — One-line config for AzuraCast, LibreTime, Radio.co, and more
- **Metrics export** — Prometheus (OpenMetrics) and StatsD exporters
- **Cross-platform** — macOS 14+, iOS 17+, tvOS 17+, watchOS 10+, visionOS 1+, Linux
- **CLI tool** — `icecast-cli` for streaming, probing, relaying, and diagnostics

### Standards

| Standard | Version | Reference |
|----------|---------|-----------|
| Icecast Source Protocol | 2.5.0 | [icecast.org](https://icecast.org/docs/) |
| ICY Metadata Protocol | — | [SHOUTcast ICY](https://cast.readme.io/docs/icy) |
| SHOUTcast DNAS | 2.6.1 | [SHOUTcast Docs](https://cast.readme.io/docs) |
| HTTP Basic Auth | RFC 7617 | [RFC 7617](https://datatracker.ietf.org/doc/html/rfc7617) |
| HTTP Digest Auth | RFC 7616 | [RFC 7616](https://datatracker.ietf.org/doc/html/rfc7616) |

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:StreamingGuide>

### Metadata

- <doc:MetadataGuide>

### Adaptive Bitrate

- <doc:AdaptiveBitrateGuide>

### Multi-Destination

- <doc:MultiDestinationGuide>

### Bandwidth Probing

- <doc:BandwidthProbingGuide>

### Connection Quality

- <doc:ConnectionQualityGuide>

### Stream Recording

- <doc:RecordingGuide>

### Relay / Ingest

- <doc:RelayGuide>

### Authentication

- <doc:AuthenticationGuide>

### Server Presets

- <doc:ServerPresetsGuide>

### Metrics Export

- <doc:MetricsExportGuide>

### Protocol Support

- <doc:ShoutcastCompatibility>

### Reliability

- <doc:ReconnectionGuide>

### Monitoring

- <doc:MonitoringGuide>

### Integration

- <doc:HLSKitBridgeGuide>

### Tools

- <doc:CLIReference>
- <doc:TestingGuide>

### Client

- ``IcecastClient``
- ``IcecastConfiguration``
- ``IcecastCredentials``
- ``ReconnectPolicy``

### Configuration

- ``AudioContentType``
- ``StationInfo``
- ``ProtocolMode``

### Audio

- ``AudioConfiguration``
- ``AACProfile``

### Metadata

- ``ICYMetadata``
- ``ICYMetadataEncoder``
- ``ICYMetadataDecoder``
- ``MetadataInterleaver``

### Admin API

- ``AdminMetadataClient``
- ``ServerStats``
- ``MountStats``

### Protocol

- ``ProtocolNegotiator``
- ``IcecastProtocol``
- ``ShoutcastProtocol``
- ``HTTPRequestBuilder``
- ``HTTPResponseParser``

### Monitoring

- ``ConnectionMonitor``
- ``ConnectionEvent``
- ``ConnectionStatistics``
- ``ConnectionState``

### Events

- ``DisconnectReason``
- ``MetadataUpdateMethod``

### Errors

- ``IcecastError``

### Adaptive Bitrate

- ``NetworkConditionMonitor``
- ``AdaptiveBitratePolicy``
- ``AdaptiveBitrateConfiguration``
- ``AudioQualityStep``
- ``BitrateRecommendation``

### Multi-Destination

- ``MultiIcecastClient``
- ``IcecastDestination``
- ``MultiIcecastEvent``
- ``MultiIcecastStatistics``

### Bandwidth Probing

- ``IcecastBandwidthProbe``
- ``IcecastProbeResult``
- ``ProbeTargetQuality``

### Connection Quality

- ``ConnectionQuality``
- ``QualityGrade``
- ``QualityRecommendationEngine``

### Recording

- ``StreamRecorder``
- ``RecordingConfiguration``
- ``RecordingStatistics``
- ``FileRotationPolicy``
- ``RecordingFormat``

### Relay

- ``IcecastRelay``
- ``IcecastRelayConfiguration``
- ``AudioChunk``
- ``RelayEvent``

### Authentication

- ``IcecastAuthentication``

### Server Presets

- ``IcecastServerPreset``
- ``PresetAuthStyle``

### Metrics

- ``IcecastMetricsExporter``
- ``MetricsExportConfiguration``
- ``PrometheusExporter``
- ``StatsDExporter``

### Transport

- ``TransportConnection``
- ``TransportConnectionFactory``
