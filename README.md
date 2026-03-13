# swift-icecast-kit

[![CI](https://github.com/atelier-socle/swift-icecast-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/atelier-socle/swift-icecast-kit/actions/workflows/ci.yml)
[![codecov](https://codecov.io/github/atelier-socle/swift-icecast-kit/graph/badge.svg?token=XTWU4FFMSN)](https://codecov.io/github/atelier-socle/swift-icecast-kit)
[![Documentation](https://img.shields.io/badge/DocC-Documentation-blue)](https://atelier-socle.github.io/swift-icecast-kit/documentation/icecastkit/)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange)
![Platforms](https://img.shields.io/badge/Platforms-macOS%20|%20iOS%20|%20tvOS%20|%20watchOS%20|%20visionOS%20|%20Linux-lightgray)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

![swift-icecast-kit](./assets/banner.png)

Pure Swift client library for streaming audio to Icecast and SHOUTcast servers. Zero dependencies on the core target. Cross-platform TCP transport with Network.framework on Apple platforms and POSIX sockets on Linux. Strict `Sendable` conformance throughout. Part of the [Atelier Socle](https://www.atelier-socle.com) streaming ecosystem.

---

## What's New in 0.3.0

- **Adaptive Bitrate** — EWMA-based congestion detection with configurable policies (conservative, responsive, aggressive, custom)
- **Multi-Destination** — Stream to multiple servers simultaneously with failure isolation
- **Bandwidth Probing** — Pre-stream upload measurement with format-aware bitrate recommendations
- **Connection Quality** — Composite score (0.0–1.0) from five weighted metrics with automatic recommendations
- **Stream Recording** — Local recording with size/time-based file rotation and filename tokens
- **Relay / Ingest** — Pull audio from existing Icecast/SHOUTcast streams with ICY demuxing
- **Advanced Authentication** — Digest (RFC 7616), Bearer token, query token, and URL-embedded credentials
- **Server Presets** — One-line configuration for AzuraCast, LibreTime, Radio.co, Centova Cast, SHOUTcast DNAS, Icecast Official, and Broadcastify
- **Metrics Export** — Prometheus (OpenMetrics) and StatsD exporters with automatic per-destination labels
- **ADTS Wrapping** — Send raw AAC access units with automatic ISO 13818-7 ADTS framing via `send(rawAAC:audioConfiguration:)`

---

## Features

- **Icecast 2.x support** — HTTP PUT (modern, Icecast 2.4+) and legacy SOURCE protocol with automatic fallback for pre-2.4.0 servers
- **SHOUTcast v1/v2** — Password authentication for single-stream servers (v1) and multi-stream with stream IDs (v2), with automatic source port calculation (listener port + 1)
- **ICY metadata** — Full binary wire format encoding/decoding with Unicode support (CJK, emoji), escaped quotes, zero-padded blocks, and configurable metadata intervals
- **Admin API** — Server-side metadata updates via `/admin/metadata`, global server stats via `/admin/stats`, and per-mountpoint stats with listener counts, bitrate, genre, and connected duration
- **Auto-reconnection** — Exponential backoff with configurable jitter, retry limits, max delay caps, and four presets (`.default`, `.aggressive`, `.conservative`, `.none`). Non-recoverable errors (auth failure, mountpoint conflict) skip reconnection entirely
- **Real-time monitoring** — `AsyncStream`-based event bus with 7 event types (connected, disconnected, reconnecting, metadataUpdated, error, statistics, protocolNegotiated), rolling-window bitrate calculation, and periodic statistics snapshots
- **Cross-platform** — macOS 14+, iOS 17+, tvOS 17+, watchOS 10+, visionOS 1+, and Linux (Ubuntu 22.04+ with Swift 6.2)
- **Adaptive bitrate** — EWMA-based congestion detection with three presets and custom policies, per-format quality steps (MP3, AAC, Opus, Vorbis), and `BitrateRecommendation` events
- **Multi-destination** — `MultiIcecastClient` actor for streaming to multiple servers with independent connections, failure isolation, live add/remove, and aggregated statistics
- **Bandwidth probing** — `IcecastBandwidthProbe` measures upload bandwidth, latency, and stability before streaming, with format-aware bitrate recommendations
- **Connection quality** — Composite quality score (0.0–1.0) from five weighted metrics (write latency, throughput, stability, send success, reconnection) with `QualityGrade` and automatic recommendations
- **Stream recording** — `StreamRecorder` actor writes audio to disk with size/time-based rotation, filename tokens (`{date}`, `{mountpoint}`, `{index}`), and format-aware extensions
- **Relay / ingest** — `IcecastRelay` actor pulls audio from existing streams with ICY metadata demuxing, content type detection, and relay-to-publish/relay-to-record chains
- **Advanced auth** — `IcecastAuthentication` enum with Digest (RFC 7616, MD5/SHA-256), Bearer token, query token, SHOUTcast v1/v2, URL-embedded credentials parsing, and credential stripping
- **Server presets** — `IcecastServerPreset` with 7 one-line configurations (AzuraCast, LibreTime, Radio.co, Centova Cast, SHOUTcast DNAS, Icecast Official, Broadcastify)
- **Metrics export** — `IcecastMetricsExporter` protocol with `PrometheusExporter` (OpenMetrics, 8 metrics, `onRender` callback) and `StatsDExporter` (UDP POSIX), automatic labels, periodic export
- **ADTS wrapping** — `send(rawAAC:audioConfiguration:)` wraps raw AAC access units in 7-byte ADTS headers (ISO 13818-7) with configurable profile, sample rate, and channel count
- **CLI tool** — `icecast-cli` for streaming, bandwidth probing, relaying, connection testing, and server diagnostics with colored terminal output and structured exit codes
- **Swift 6.2 strict concurrency** — Actors for stateful types, `Sendable` everywhere, `async`/`await` throughout, zero `@unchecked Sendable` or `nonisolated(unsafe)`
- **Zero core dependencies** — The `IcecastKit` target has no third-party dependencies. Only `swift-argument-parser` for the CLI and `swift-crypto` conditionally on Linux

---

## Standards

| Standard | Version | Reference |
|----------|---------|-----------|
| Icecast Source Protocol | 2.5.0 | [icecast.org](https://icecast.org/docs/) |
| ICY Metadata Protocol | — | [SHOUTcast ICY](https://cast.readme.io/docs/icy) |
| SHOUTcast DNAS | 2.6.1 | [SHOUTcast Docs](https://cast.readme.io/docs) |
| HTTP Basic Auth | RFC 7617 | [RFC 7617](https://datatracker.ietf.org/doc/html/rfc7617) |
| HTTP Digest Auth | RFC 7616 | [RFC 7616](https://datatracker.ietf.org/doc/html/rfc7616) |
| ADTS (AAC Transport) | ISO 13818-7 | [ISO 13818-7](https://www.iso.org/standard/43345.html) |

---

## Quick Start

Connect to an Icecast server, stream audio data, update the now-playing metadata, and disconnect gracefully:

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

---

## Installation

### Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/atelier-socle/swift-icecast-kit.git", from: "0.3.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["IcecastKit"]
)
```

---

## Platform Support

| Platform | Minimum Version |
|----------|----------------|
| macOS | 14+ |
| iOS | 17+ |
| tvOS | 17+ |
| watchOS | 10+ |
| visionOS | 1+ |
| Linux | Swift 6.2 (Ubuntu 22.04+) |

---

## Usage

### Icecast PUT Streaming with Station Info

Configure a full station with name, genre, bitrate, sample rate, and channels. The client negotiates the best protocol automatically — trying modern HTTP PUT first, then falling back to legacy SOURCE if the server is pre-2.4.0:

```swift
import IcecastKit

// Describe the station — these values become ice-* headers during the handshake
let stationInfo = StationInfo(
    name: "Radio Showcase",
    description: "A showcase test station",
    url: "https://radio.example.com",
    genre: "Electronic",
    isPublic: true,
    bitrate: 128,
    sampleRate: 44100,
    channels: 2
)

let configuration = IcecastConfiguration(
    host: "radio.example.com",
    port: 8000,
    mountpoint: "/live.mp3",
    stationInfo: stationInfo
)
let credentials = IcecastCredentials(password: "hackme")

let client = IcecastClient(
    configuration: configuration,
    credentials: credentials
)

// Connect — negotiates PUT protocol, authenticates, transitions to .connected
try await client.connect()

// Stream audio data — first send transitions state to .streaming
// IcecastKit does NOT enforce pacing — send at your audio bitrate
let chunkSize = 4096
let chunkCount = 480_000 / chunkSize  // ~30s of 128 kbps audio
for _ in 0..<chunkCount {
    try await client.send(Data(repeating: 0xFF, count: chunkSize))
}

// Update the now-playing metadata — listeners see this in their player
try await client.updateMetadata(ICYMetadata(streamTitle: "Artist 1 - Song 1"))
try await client.updateMetadata(ICYMetadata(streamTitle: "Artist 2 - Song 2"))

// Check statistics at any time
let stats = await client.statistics
// stats.bytesSent == 479,232 (chunkCount * chunkSize)
// stats.metadataUpdateCount == 2
// stats.connectedSince != nil

// Graceful disconnect — closes TCP connection, emits .disconnected event
await client.disconnect()
```

### Sending Raw AAC with ADTS Wrapping

If your audio pipeline produces raw AAC access units (e.g., from `AVAudioEngine` or `AudioToolbox`), use `send(rawAAC:audioConfiguration:)` to let IcecastKit wrap each frame with a 7-byte ADTS header (ISO 13818-7) before sending:

```swift
import IcecastKit

let client = IcecastClient(
    configuration: IcecastConfiguration(host: "radio.example.com", mountpoint: "/live.aac", contentType: .aac),
    credentials: IcecastCredentials(password: "hackme")
)

try await client.connect()

// Describe the audio format
let audioConfig = AudioConfiguration(sampleRate: 44100, channelCount: 2)

// Each call wraps raw AAC in an ADTS frame and sends it
for rawFrame in rawAACFrames {
    try await client.send(rawAAC: rawFrame, audioConfiguration: audioConfig)
}

await client.disconnect()
```

If your data already has ADTS headers (e.g., read from an `.aac` file), use the regular `send(_:)` method.

### URL-Based Configuration

Parse a connection URL into a configuration and credentials in one call. Supports `icecast://`, `shoutcast://`, `http://`, and `https://` schemes:

```swift
let (config, creds) = try IcecastConfiguration.from(
    url: "icecast://source:hackme@radio.example.com:8000/live.mp3"
)
let client = IcecastClient(configuration: config, credentials: creds)
try await client.connect()
```

### SHOUTcast v1 Streaming

SHOUTcast v1 uses password-only authentication. IcecastKit automatically connects to the source port (listener port + 1) and sends the password line followed by `icy-*` stream headers:

```swift
let configuration = IcecastConfiguration(
    host: "shoutcast.example.com",
    port: 8000,                      // Listener port — connects to 8001 (source port)
    mountpoint: "/stream",
    stationInfo: StationInfo(name: "SHOUTcast Radio", genre: "Jazz", bitrate: 128),
    protocolMode: .shoutcastV1       // Explicit SHOUTcast v1 mode
)
let credentials = IcecastCredentials.shoutcast(password: "shoutpass")

let client = IcecastClient(configuration: configuration, credentials: credentials)
try await client.connect()

// Send audio data
try await client.send(audioData)
await client.disconnect()
```

### SHOUTcast v2 Multi-Stream

SHOUTcast v2 extends v1 with stream IDs for multi-stream servers. The password is sent as `password:#streamId`:

```swift
let configuration = IcecastConfiguration(
    host: "shoutcast.example.com",
    port: 8000,
    mountpoint: "/stream",
    stationInfo: StationInfo(name: "SHOUTcast v2 Radio", bitrate: 192),
    protocolMode: .shoutcastV2(streamId: 3)   // Stream ID 3
)
let credentials = IcecastCredentials.shoutcast(password: "v2pass")

let client = IcecastClient(configuration: configuration, credentials: credentials)
try await client.connect()
// Password sent as "v2pass:#3\r\n" on source port 8001

try await client.send(audioData)
await client.disconnect()
```

### Real-Time Event Monitoring

Subscribe to the `AsyncStream`-based event bus to react to connection state changes, metadata updates, errors, and periodic statistics in real time:

```swift
let client = IcecastClient(
    configuration: configuration,
    credentials: credentials
)

// Iterate the event stream in a background task
let eventTask = Task {
    for await event in client.events {
        switch event {
        case .connected(let host, let port, let mountpoint, let protocolName):
            print("Connected to \(host):\(port)\(mountpoint) via \(protocolName)")
        case .disconnected(let reason):
            print("Disconnected: \(reason)")
        case .reconnecting(let attempt, let delay):
            print("Reconnecting (attempt \(attempt), next retry in \(delay)s)")
        case .metadataUpdated(let metadata, let method):
            print("Metadata: \(metadata.streamTitle ?? "none") via \(method)")
        case .error(let error):
            print("Error: \(error)")
        case .statistics(let stats):
            print("Stats: \(stats.bytesSent) bytes, \(stats.currentBitrate) bps")
        case .protocolNegotiated(let mode):
            print("Protocol: \(mode)")
        }
    }
}

try await client.connect()
try await client.send(audioData)
await client.disconnect()
eventTask.cancel()
```

### Connection Statistics

Access real-time statistics at any point during a streaming session — bytes sent, streaming duration, average and current bitrate, metadata update count, reconnection count, and send error count:

```swift
try await client.connect()

// Stream 80,000 bytes in 4,000-byte chunks
for _ in 0..<20 {
    try await client.send(Data(repeating: 0xAA, count: 4000))
}

// Update metadata 5 times
for i in 0..<5 {
    try await client.updateMetadata(ICYMetadata(streamTitle: "Track \(i + 1)"))
}

let stats = await client.statistics
// stats.bytesSent == 80,000
// stats.bytesTotal == 80,000
// stats.metadataUpdateCount == 5
// stats.duration > 0
// stats.connectedSince != nil
// stats.reconnectionCount == 0

await client.disconnect()
// After disconnect: stats.connectedSince == nil, but bytesSent is preserved
```

### Auto-Reconnection with Exponential Backoff

Configure automatic reconnection when a connection is lost mid-stream. IcecastKit provides four presets and supports fully custom policies with jitter to prevent thundering herd problems:

```swift
// Default policy: 10 retries, 1s initial delay, 2x backoff, 60s max, 0.25 jitter
let client1 = IcecastClient(
    configuration: configuration,
    credentials: credentials,
    reconnectPolicy: .default
)

// Aggressive: fast retries for low-latency scenarios
let client2 = IcecastClient(
    configuration: configuration,
    credentials: credentials,
    reconnectPolicy: .aggressive  // 20 retries, 0.5s initial, 1.5x, 30s max
)

// Conservative: slow retries for unreliable networks
let client3 = IcecastClient(
    configuration: configuration,
    credentials: credentials,
    reconnectPolicy: .conservative  // 5 retries, 5s initial, 3x, 120s max
)

// Custom policy for specific requirements
let customPolicy = ReconnectPolicy(
    maxRetries: 3,
    initialDelay: 0.02,
    maxDelay: 0.1,
    backoffMultiplier: 2.0,
    jitterFactor: 0.0
)
let client4 = IcecastClient(
    configuration: configuration,
    credentials: credentials,
    reconnectPolicy: customPolicy
)
```

The reconnection delay follows: `min(initialDelay x backoffMultiplier^attempt, maxDelay) +/- jitter`. Non-recoverable errors (authentication failure, mountpoint in use, content type rejected) skip reconnection and transition directly to `.failed`. Calling `disconnect()` during reconnection cancels the loop immediately.

### ICY Metadata Encoding and Decoding

Encode metadata into the ICY binary wire format for inline stream embedding, and decode it back. Supports Unicode, escaped quotes, and custom fields:

```swift
// Create metadata with Unicode and custom fields
let metadata = ICYMetadata(
    streamTitle: "日本語タイトル 🎵",
    streamUrl: "https://example.com",
    customFields: ["CustomKey": "value"]
)

// Encode to binary wire format
let encoder = ICYMetadataEncoder()
let encoded = try encoder.encode(metadata)
// Wire format: byte 0 = length N, followed by N x 16 bytes of zero-padded metadata string

// Decode back from binary
let decoder = ICYMetadataDecoder()
let (decoded, bytesConsumed) = try decoder.decode(from: encoded)
// decoded.streamTitle == "日本語タイトル 🎵"
// bytesConsumed == 1 + N * 16

// Get URL-encoded title for the admin API
let urlEncoded = metadata.urlEncodedSong()
// Spaces become "+", special characters are percent-encoded
```

### Metadata Interleaving

Insert metadata blocks into an audio stream at fixed byte intervals. The `MetadataInterleaver` actor tracks its position across multiple calls, so you can feed audio data in any chunk size:

```swift
let interleaver = MetadataInterleaver(metaint: 8192)

// Set the current metadata — inserted at every 8192-byte boundary
await interleaver.updateMetadata(ICYMetadata(streamTitle: "Artist - Song"))

// Process audio data — metadata blocks are inserted at the correct positions
// Output: [audio: 8192 bytes] [metadata block] [audio: 8192 bytes] [metadata block] ...
let output = try await interleaver.interleave(audioData)

// Clear metadata — empty blocks (0x00) are inserted instead
await interleaver.updateMetadata(nil)
```

### Admin API: Metadata Updates and Server Stats

Update stream metadata server-side via the Icecast admin HTTP API (preferred over inline metadata). Also query global server statistics and per-mountpoint stats:

```swift
let adminClient = AdminMetadataClient(
    host: "radio.example.com",
    port: 8000,
    useTLS: false,
    credentials: IcecastCredentials(username: "admin", password: "adminpass")
)

// Update metadata — sends GET /admin/metadata?mount=/live.mp3&mode=updinfo&song=...
let metadata = ICYMetadata(streamTitle: "Test & Title")
try await adminClient.updateMetadata(metadata, mountpoint: "/live.mp3")

// Fetch global server statistics (version, active mountpoints, total listeners)
let serverStats = try await adminClient.fetchServerStats()
// serverStats.serverVersion == "Icecast 2.5.0"
// serverStats.activeMountpoints == ["/live.mp3", "/ambient.ogg"]
// serverStats.totalListeners == 57
// serverStats.totalSources == 2

// Fetch stats for a specific mountpoint
let mountStats = try await adminClient.fetchMountStats(mountpoint: "/live.mp3")
// mountStats.listeners == 42
// mountStats.streamTitle == "Live Stream"
// mountStats.bitrate == 128
// mountStats.genre == "Rock"
// mountStats.contentType == "audio/mpeg"
// mountStats.connectedDuration == 3600
```

When `adminCredentials` are set on `IcecastConfiguration`, `IcecastClient.updateMetadata()` automatically uses the admin API and falls back to inline metadata if the admin endpoint returns 404:

```swift
let config = IcecastConfiguration(
    host: "radio.example.com",
    mountpoint: "/live.mp3",
    adminCredentials: IcecastCredentials(username: "admin", password: "adminpass")
)
let client = IcecastClient(configuration: config, credentials: sourceCredentials)
try await client.connect()

// Automatically uses admin API; falls back to inline if unavailable
try await client.updateMetadata(ICYMetadata(streamTitle: "Admin Song"))
```

### Content Type Detection

Auto-detect the audio content type from a filename extension:

```swift
AudioContentType.detect(from: "music.mp3")   // .mp3 (audio/mpeg)
AudioContentType.detect(from: "song.aac")    // .aac (audio/aac)
AudioContentType.detect(from: "audio.ogg")   // .oggVorbis (application/ogg)
AudioContentType.detect(from: "voice.opus")  // .oggOpus (audio/ogg)
```

### Concurrent Operations

`IcecastClient` is an actor, so all operations are inherently thread-safe. You can safely call `send()` and `updateMetadata()` from multiple concurrent tasks without data races:

```swift
try await client.connect()
try await client.send(Data(repeating: 0x00, count: 128))

await withTaskGroup(of: Void.self) { group in
    // 10 concurrent metadata updates
    for i in 0..<10 {
        group.addTask {
            try? await client.updateMetadata(
                ICYMetadata(streamTitle: "Concurrent Track \(i)")
            )
        }
    }
    // 5 concurrent sends
    for i in 0..<5 {
        group.addTask {
            try? await client.send(Data(repeating: UInt8(i), count: 256))
        }
    }
}

let stats = await client.statistics
// stats.metadataUpdateCount == 10
// stats.bytesSent == 1408 (128 + 5 x 256)
```

### Adaptive Bitrate

Monitor network conditions in real time and receive bitrate recommendations. Three presets (conservative, responsive, aggressive) plus full custom configuration:

```swift
let config = IcecastConfiguration(
    host: "radio.example.com",
    mountpoint: "/live.mp3",
    adaptiveBitrate: .conservative
)
let client = IcecastClient(configuration: config, credentials: credentials)
try await client.connect()

for await event in client.events {
    if case .bitrateRecommendation(let rec) = event {
        print("\(rec.direction): \(rec.recommendedBitrate) bps (\(rec.reason))")
    }
}
```

The `NetworkConditionMonitor` detects congestion via EWMA latency spikes, RTT spikes, and bandwidth slowdowns. `AudioQualityStep` provides per-format bitrate tiers (MP3: 7 steps from 32–320 kbps, plus AAC, Opus, Vorbis).

### Multi-Destination Publishing

Stream to multiple servers simultaneously with independent failure isolation:

```swift
let multi = MultiIcecastClient()

try await multi.addDestination("primary", configuration: IcecastConfiguration(
    host: "radio1.example.com", mountpoint: "/live.mp3",
    credentials: IcecastCredentials(password: "secret1")
))
try await multi.addDestination("backup", configuration: IcecastConfiguration(
    host: "backup.example.com", mountpoint: "/live.mp3",
    credentials: IcecastCredentials(password: "secret2")
))

try await multi.connectAll()
try await multi.send(audioData)

let stats = await multi.statistics
print("Connected: \(stats.connectedCount)/\(stats.totalCount)")
```

Add or remove destinations live while streaming. Each destination has its own reconnection policy.

### Bandwidth Probing

Measure upload bandwidth and latency before committing to a live stream:

```swift
let probe = IcecastBandwidthProbe()
let result = try await probe.measure(
    host: "radio.example.com",
    mountpoint: "/probe",
    credentials: IcecastCredentials(password: "hackme"),
    contentType: .mp3,
    duration: 5.0
)
print("Bandwidth: \(result.uploadBandwidth) bps")
print("Latency: \(result.averageWriteLatency) ms (\(result.latencyClass))")
print("Stability: \(result.stabilityScore)/100")
print("Recommended: \(result.recommendedBitrate) bps")
```

### Connection Quality

Real-time quality scoring from five weighted metrics (write latency 30%, throughput 25%, stability 20%, send success 15%, reconnection 10%):

```swift
let quality = ConnectionQuality.from(statistics: stats)
print("\(quality.grade.label): \(quality.score)")
// "Excellent: 0.95"

// Grades: .excellent (0.91+), .good (0.71+), .fair (0.51+), .poor (0.31+), .critical (<0.31)
// QualityGrade is Comparable: .excellent > .good > .fair > .poor > .critical

let engine = QualityRecommendationEngine()
if let rec = engine.recommendation(for: quality) {
    print("Recommendation: \(rec)")
}
```

Quality events arrive via the event stream: `.qualityChanged(_:)` and `.qualityWarning(_:)`.

### Stream Recording

Record streamed audio to disk with automatic file rotation:

```swift
let recorder = StreamRecorder(configuration: RecordingConfiguration(
    directory: "/recordings",
    contentType: .mp3,
    maxFileSize: 50_000_000,  // Rotate at 50 MB
    filenamePattern: "{mountpoint}_{index}"
))
try await recorder.start(mountpoint: "/live.mp3")
try await recorder.write(audioData)
let stats = try await recorder.stop()
print("Files created: \(stats.filesCreated)")
```

Integrates with `IcecastClient` via `IcecastConfiguration.recording` for auto-start recording. Events: `.recordingStarted`, `.recordingStopped`, `.recordingFileRotated`.

### Relay / Ingest

Pull audio from an existing Icecast/SHOUTcast stream:

```swift
let relay = IcecastRelay(configuration: IcecastRelayConfiguration(
    sourceURL: "http://radio.example.com:8000/live.mp3"
))
try await relay.connect()

for await chunk in relay.audioStream {
    print("\(chunk.data.count) bytes, offset \(chunk.byteOffset)")
    if let meta = chunk.metadata {
        print("Now playing: \(meta.streamTitle ?? "unknown")")
    }
}
```

Chain with `IcecastClient` for relay-to-publish, or with `StreamRecorder` for relay-to-record.

### Advanced Authentication

Six authentication methods via `IcecastAuthentication`:

```swift
// Digest (RFC 7616) — challenge-response, password never on the wire
let config = IcecastConfiguration(
    host: "radio.example.com", mountpoint: "/live.mp3",
    authentication: .digest(username: "source", password: "hackme")
)

// Bearer token
let bearer = IcecastConfiguration(
    host: "radio.example.com", mountpoint: "/live.mp3",
    authentication: .bearer(token: "my-api-token-12345")
)

// URL-embedded credentials
let auth = IcecastAuthentication.fromURL("http://admin:secret@radio.example.com:8000/live.mp3")
// .basic(username: "admin", password: "secret")

let clean = IcecastAuthentication.stripCredentials(from: "http://admin:secret@radio.example.com/live.mp3")
// "http://radio.example.com/live.mp3"
```

| Type | Description |
|------|-------------|
| `.basic` | HTTP Basic (RFC 7617) |
| `.digest` | HTTP Digest (RFC 7616, MD5/SHA-256) |
| `.bearer` | Bearer token |
| `.queryToken` | Token in URL query string |
| `.shoutcast` | SHOUTcast v1 password-only |
| `.shoutcastV2` | SHOUTcast v2 with stream ID |

### Server Presets

One-line configuration for 7 popular platforms:

```swift
let config = IcecastServerPreset.azuracast.configuration(
    host: "mystation.azuracast.com",
    password: "my-source-password"
)
// Preconfigured: port 8000, /radio.mp3, PUT protocol, Basic auth

let client = IcecastClient(
    configuration: config,
    credentials: config.credentials ?? IcecastCredentials(password: "fallback")
)
```

| Preset | Port | Auth | Protocol |
|--------|------|------|----------|
| `.azuracast` | 8000 | Basic | Icecast PUT |
| `.libretime` | 8000 | Basic | Icecast PUT |
| `.radioCo` | 8000 | Bearer | Icecast PUT |
| `.centovaCast` | 8000 | SHOUTcast v2 | SHOUTcast v2 |
| `.shoutcastDNAS` | 8000 | Password | SHOUTcast v1 |
| `.icecastOfficial` | 8000 | Basic | Icecast PUT |
| `.broadcastify` | 80 | Bearer | Icecast PUT |

### Metrics Export

Export streaming metrics to Prometheus or StatsD:

```swift
// Prometheus — OpenMetrics format with 8 metrics
let exporter = PrometheusExporter { output in
    // Serve at /metrics endpoint
}
await client.setMetricsExporter(exporter, interval: 10.0)

// StatsD — UDP datagrams
let statsD = StatsDExporter(host: "127.0.0.1", port: 8125, prefix: "radio")
await client.setMetricsExporter(statsD, interval: 10.0)
```

Exported metrics: `bytes_sent`, `stream_duration_seconds`, `current_bitrate`, `metadata_updates_total`, `reconnections_total`, `write_latency_ms`, `peak_bitrate`, `connection_quality_score`. Labels are auto-generated from configuration (mountpoint, server) with consumer overrides.

---

## CLI

`icecast-cli` provides command-line streaming, connection testing, and server diagnostics with colored terminal output and structured exit codes (0 = success, 2 = connection error, 3 = auth error, 4 = file error, 6 = server error, 7 = timeout).

### Installation

```bash
swift build -c release
cp .build/release/icecast-cli /usr/local/bin/
```

### Commands

| Command | Description |
|---------|-------------|
| `stream` | Stream an audio file with optional multi-destination, auth types, looping, and auto-reconnect |
| `probe` | Measure upload bandwidth and latency to a server |
| `relay` | Pull audio from a source and optionally re-publish or record |
| `test-connection` | Test TCP connectivity, protocol negotiation, and authentication, then disconnect |
| `info` | Query global server stats or per-mountpoint stats via the admin API |

### Examples

```bash
# Stream an MP3 file with metadata
icecast-cli stream music.mp3 --host radio.example.com --password hackme --title "My Show"

# Test connectivity and authentication
icecast-cli test-connection --host radio.example.com --password hackme

# Query global server information via admin API
icecast-cli info --host radio.example.com --admin-pass hackme

# Query a specific mountpoint
icecast-cli info --host radio.example.com --admin-pass hackme --mountpoint /live.mp3

# Stream with SHOUTcast v1 protocol and continuous looping
icecast-cli stream music.mp3 --password hackme --loop --protocol shoutcast-v1

# Stream with SHOUTcast v2 multi-stream (stream ID 3)
icecast-cli stream music.mp3 --password hackme --protocol shoutcast-v2:3

# Stream to multiple destinations
icecast-cli stream music.mp3 \
    --dest "primary:radio1.example.com:8000:/live.mp3:secret1" \
    --dest "backup:backup.example.com:8000:/live.mp3:secret2"

# Stream with digest authentication
icecast-cli stream music.mp3 --host radio.example.com --password hackme --auth-type digest

# Stream with bearer token
icecast-cli stream music.mp3 --host radio.example.com --auth-type bearer --token my-api-token

# Probe bandwidth before streaming
icecast-cli probe --host radio.example.com --port 8000 --password hackme --duration 10

# Relay and record a stream
icecast-cli relay --source http://radio.example.com:8000/live.mp3 --record /recordings/ --duration 3600
```

See the [CLI Reference](https://atelier-socle.github.io/swift-icecast-kit/documentation/icecastkit/clireference) for the full command documentation with all options and flags.

---

## Architecture

```
Sources/
├── IcecastKit/                  # Core library (zero dependencies)
│   ├── Audio/                   # ADTS frame builder, audio configuration, AAC profiles
│   ├── Client/                  # IcecastClient, configuration, credentials, state, reconnect
│   ├── Protocol/                # Protocol negotiation, HTTP request/response, Icecast/SHOUTcast
│   ├── Metadata/                # ICY metadata encode/decode, interleaver, admin API, stats
│   ├── Transport/               # TCP transport (NWConnection / POSIX sockets)
│   ├── Monitoring/              # ConnectionMonitor, events, statistics
│   ├── AdaptiveBitrate/         # NetworkConditionMonitor, policies, quality steps
│   ├── MultiClient/             # MultiIcecastClient, destinations, aggregated stats
│   ├── Probe/                   # IcecastBandwidthProbe, probe result, target quality
│   ├── Quality/                 # ConnectionQuality, QualityGrade, recommendations
│   ├── Recording/               # StreamRecorder, rotation policy, recording stats
│   ├── Relay/                   # IcecastRelay, AudioChunk, ICYStreamDemuxer
│   ├── Authentication/          # IcecastAuthentication, DigestAuth, Bearer, QueryToken
│   ├── ServerPresets/           # IcecastServerPreset, PresetAuthStyle
│   ├── Metrics/                 # Exporters (Prometheus, StatsD), protocol
│   ├── Errors/                  # Typed error hierarchy
│   └── Extensions/              # Data + String helpers
├── IcecastKitCommands/          # CLI commands (stream, probe, relay, test-connection, info)
└── IcecastKitCLI/               # CLI entry point (@main)
```

---

## Documentation

Full API documentation is available as a DocC catalog:

- **Online**: [atelier-socle.github.io/swift-icecast-kit](https://atelier-socle.github.io/swift-icecast-kit/documentation/icecastkit/)
- **Xcode**: Open the project and select **Product > Build Documentation**

---

## Ecosystem

swift-icecast-kit is part of the Atelier Socle streaming ecosystem:

- [PodcastFeedMaker](https://github.com/atelier-socle/podcast-feed-maker) — Podcast RSS feed generation
- [swift-hls-kit](https://github.com/atelier-socle/swift-hls-kit) — HTTP Live Streaming
- **swift-icecast-kit** (this library) — Icecast/SHOUTcast streaming
- swift-rtmp-kit (coming soon) — RTMP streaming
- swift-srt-kit (coming soon) — SRT streaming

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute.

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).

Copyright 2026 [Atelier Socle SAS](https://www.atelier-socle.com). See [NOTICE](NOTICE) for details.
