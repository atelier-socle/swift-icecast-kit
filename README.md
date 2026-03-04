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

## Features

- **Icecast 2.x support** — HTTP PUT (modern, Icecast 2.4+) and legacy SOURCE protocol with automatic fallback for pre-2.4.0 servers
- **SHOUTcast v1/v2** — Password authentication for single-stream servers (v1) and multi-stream with stream IDs (v2), with automatic source port calculation (listener port + 1)
- **ICY metadata** — Full binary wire format encoding/decoding with Unicode support (CJK, emoji), escaped quotes, zero-padded blocks, and configurable metadata intervals
- **Admin API** — Server-side metadata updates via `/admin/metadata`, global server stats via `/admin/stats`, and per-mountpoint stats with listener counts, bitrate, genre, and connected duration
- **Auto-reconnection** — Exponential backoff with configurable jitter, retry limits, max delay caps, and four presets (`.default`, `.aggressive`, `.conservative`, `.none`). Non-recoverable errors (auth failure, mountpoint conflict) skip reconnection entirely
- **Real-time monitoring** — `AsyncStream`-based event bus with 7 event types (connected, disconnected, reconnecting, metadataUpdated, error, statistics, protocolNegotiated), rolling-window bitrate calculation, and periodic statistics snapshots
- **Cross-platform** — macOS 14+, iOS 17+, tvOS 17+, watchOS 10+, visionOS 1+, and Linux (Ubuntu 22.04+ with Swift 6.2)
- **CLI tool** — `icecast-cli` for streaming audio files, testing connections, and querying server info with colored terminal output and structured exit codes
- **Swift 6.2 strict concurrency** — Actors for stateful types, `Sendable` everywhere, `async`/`await` throughout, zero `@unchecked Sendable` or `nonisolated(unsafe)`
- **Zero core dependencies** — The `IcecastKit` target has no third-party dependencies. Only `swift-argument-parser` for the CLI

---

## Standards

| Standard | Version | Reference |
|----------|---------|-----------|
| Icecast Source Protocol | 2.5.0 | [icecast.org](https://icecast.org/docs/) |
| ICY Metadata Protocol | — | [SHOUTcast ICY](https://cast.readme.io/docs/icy) |
| SHOUTcast DNAS | 2.6.1 | [SHOUTcast Docs](https://cast.readme.io/docs) |
| HTTP Basic Auth | RFC 7617 | [RFC 7617](https://datatracker.ietf.org/doc/html/rfc7617) |

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
    .package(url: "https://github.com/atelier-socle/swift-icecast-kit.git", from: "0.2.0")
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
| `stream` | Stream an audio file to an Icecast/SHOUTcast server with optional looping and auto-reconnect |
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
```

See the [CLI Reference](https://atelier-socle.github.io/swift-icecast-kit/documentation/icecastkit/clireference) for the full command documentation with all options and flags.

---

## Architecture

```
Sources/
├── IcecastKit/                  # Core library (zero dependencies)
│   ├── Client/                  # IcecastClient, configuration, credentials, state, reconnect
│   ├── Protocol/                # Protocol negotiation, HTTP request/response, Icecast/SHOUTcast
│   ├── Metadata/                # ICY metadata encode/decode, interleaver, admin API, stats
│   ├── Transport/               # TCP transport (NWConnection / POSIX sockets)
│   ├── Monitoring/              # ConnectionMonitor, events, statistics
│   ├── Errors/                  # Typed error hierarchy (27 cases across 7 categories)
│   └── Extensions/              # Data + String helpers
├── IcecastKitCommands/          # CLI command implementations (stream, test-connection, info)
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
