# Relay / Ingest

Pull audio from an Icecast or SHOUTcast source and process it locally.

@Metadata {
    @PageKind(article)
}

## Overview

``IcecastRelay`` connects to an existing Icecast or SHOUTcast stream as a listener and delivers audio chunks through an `AsyncStream`. This enables relay chains (pull → re-publish), local recording, and audio processing pipelines.

### Connecting to a Source

```swift
let config = IcecastRelayConfiguration(
    sourceURL: "http://radio.example.com:8000/live.mp3"
)
let relay = IcecastRelay(configuration: config)

try await relay.connect()
print("Connected: \(await relay.isConnected)")
print("Content type: \(await relay.detectedContentType ?? .mp3)")
print("Server: \(await relay.serverVersion ?? "unknown")")
```

### Relay Configuration

``IcecastRelayConfiguration`` controls the relay connection:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sourceURL` | `String` | (required) | Source stream URL |
| `credentials` | ``IcecastCredentials``? | `nil` | Authentication credentials |
| `requestICYMetadata` | `Bool` | `true` | Request inline ICY metadata |
| `bufferSize` | `Int` | 65536 | Receive buffer size |
| `userAgent` | `String` | `"IcecastKit/0.2.0"` | User-Agent header |
| `reconnectPolicy` | ``ReconnectPolicy``? | `nil` | Auto-reconnect policy |
| `connectionTimeout` | `TimeInterval` | 10.0 | Connection timeout |
| `authentication` | ``IcecastAuthentication``? | `nil` | Advanced authentication |

### Receiving Audio

Audio data arrives as ``AudioChunk`` values through the `audioStream`:

```swift
for await chunk in relay.audioStream {
    print("Received \(chunk.data.count) bytes")
    print("Content type: \(chunk.contentType)")
    print("Byte offset: \(chunk.byteOffset)")
    if let meta = chunk.metadata {
        print("Title: \(meta.streamTitle ?? "none")")
    }
}
```

``AudioChunk`` carries:

| Property | Type | Description |
|----------|------|-------------|
| `data` | `Data` | Raw audio bytes |
| `metadata` | ``ICYMetadata``? | ICY metadata if present at this position |
| `contentType` | ``AudioContentType`` | Detected audio format |
| `timestamp` | `Date` | When the chunk was received |
| `byteOffset` | `Int64` | Total byte offset in the stream |

### ICY Stream Demuxing

When the source server advertises `icy-metaint`, `ICYStreamDemuxer` automatically separates audio bytes from inline ICY metadata blocks:

```swift
var demuxer = ICYStreamDemuxer(metaint: 8192)
let result = demuxer.feed(rawData)
// result.audioBytes — pure audio data
// result.metadata   — parsed ICYMetadata, if present in this chunk
```

When `metaint` is `nil`, all data passes through as audio:

```swift
var demuxer = ICYStreamDemuxer(metaint: nil)
let result = demuxer.feed(rawData)
// result.audioBytes == rawData
// result.metadata == nil
```

### Relay Events

``RelayEvent`` reports connection lifecycle:

| Event | Description |
|-------|-------------|
| `.connected(serverVersion:contentType:)` | Connected to the source |
| `.disconnected(error:)` | Disconnected from the source |
| `.reconnecting(attempt:)` | Attempting to reconnect |
| `.reconnected` | Successfully reconnected |
| `.metadataUpdated(_:)` | ICY metadata changed |
| `.streamEnded` | Source stream ended |

```swift
for await event in relay.events {
    switch event {
    case .connected(let version, let type):
        print("Connected to \(version ?? "unknown"), type: \(type ?? .mp3)")
    case .metadataUpdated(let meta):
        print("Now playing: \(meta.streamTitle ?? "unknown")")
    case .disconnected(let error):
        print("Disconnected: \(error?.localizedDescription ?? "clean")")
    default:
        break
    }
}
```

### Relay Properties

| Property | Type | Description |
|----------|------|-------------|
| `isConnected` | `Bool` | Connection status |
| `currentMetadata` | ``ICYMetadata``? | Latest metadata |
| `detectedContentType` | ``AudioContentType``? | Content type from headers |
| `bytesReceived` | `Int64` | Total bytes received |
| `serverVersion` | `String?` | Server version string |
| `stationName` | `String?` | Station name from headers |

### Relay → Re-publish Chain

Pull from one server and push to another:

```swift
let relay = IcecastRelay(
    configuration: IcecastRelayConfiguration(
        sourceURL: "http://source.example.com:8000/live.mp3"
    )
)
try await relay.connect()

let client = IcecastClient(
    configuration: IcecastConfiguration(
        host: "dest.example.com",
        mountpoint: "/relay.mp3"
    ),
    credentials: IcecastCredentials(password: "hackme")
)
try await client.connect()

for await chunk in relay.audioStream {
    try await client.send(chunk.data)
}
```

### Relay → Record Chain

Pull from a server and record to disk:

```swift
let relay = IcecastRelay(
    configuration: IcecastRelayConfiguration(
        sourceURL: "http://radio.example.com:8000/live.mp3"
    )
)
try await relay.connect()

let recorder = StreamRecorder(
    configuration: RecordingConfiguration(
        directory: "/recordings",
        contentType: .mp3
    )
)
try await recorder.start()

for await chunk in relay.audioStream {
    try await recorder.write(chunk.data)
}
```

### CLI Usage

The `icecast-cli relay` command pulls and optionally re-publishes or records:

```bash
# Relay and re-publish
icecast-cli relay \
    --source http://source.example.com:8000/live.mp3 \
    --dest "relay1:dest.example.com:8000:/relay.mp3:hackme"

# Relay and record
icecast-cli relay \
    --source http://radio.example.com:8000/live.mp3 \
    --record /recordings/ \
    --duration 3600
```

## Next Steps

- <doc:RecordingGuide> — Recording configuration and file rotation
- <doc:AuthenticationGuide> — Authentication for relay sources
- <doc:StreamingGuide> — Publishing audio to servers
