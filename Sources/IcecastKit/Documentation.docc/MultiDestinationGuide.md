# Multi-Destination Streaming

Stream audio to multiple Icecast or SHOUTcast servers simultaneously.

@Metadata {
    @PageKind(article)
}

## Overview

``MultiIcecastClient`` manages multiple streaming destinations from a single audio source. Each destination operates independently with its own connection, authentication, and reconnection — a failure on one destination does not affect the others.

### Architecture

``MultiIcecastClient`` is an actor that wraps multiple ``IcecastClient`` instances, each identified by a unique string label. The client handles connection management, data distribution, and aggregated event reporting.

### Adding Destinations

Register destinations before connecting:

```swift
let multi = MultiIcecastClient()

let primaryConfig = IcecastConfiguration(
    host: "radio1.example.com",
    mountpoint: "/live.mp3",
    credentials: IcecastCredentials(password: "secret1")
)
let backupConfig = IcecastConfiguration(
    host: "backup.example.com",
    mountpoint: "/live.mp3",
    credentials: IcecastCredentials(password: "secret2")
)

try await multi.addDestination("primary", configuration: primaryConfig)
try await multi.addDestination("backup", configuration: backupConfig)
```

Duplicate labels throw ``IcecastError``. Each configuration must include credentials.

### Connecting and Streaming

Connect all destinations at once, then send audio data:

```swift
try await multi.connectAll()

let audioData = Data(repeating: 0xFF, count: 4096)
try await multi.send(audioData)
```

``MultiIcecastClient/send(_:)`` distributes data to all connected destinations. If a destination is disconnected or reconnecting, it is skipped without affecting the others.

### Live Destination Management

Add or remove destinations while streaming:

```swift
// Add a new destination that connects immediately
try await multi.addDestinationLive(
    "cdn",
    configuration: IcecastConfiguration(
        host: "cdn.example.com",
        mountpoint: "/live.mp3",
        credentials: IcecastCredentials(password: "cdn-pass")
    )
)

// Remove a destination (disconnects cleanly)
await multi.removeDestination(label: "backup")
```

### Failure Isolation

Each destination has its own connection and reconnection policy. A failure on one destination does not propagate to others:

```swift
// If backup fails, primary continues streaming
let stats = await multi.statistics
print("Connected: \(stats.connectedCount)/\(stats.totalCount)")
```

When **all** destinations fail during ``MultiIcecastClient/connectAll()``, the method throws an ``IcecastError``.

### Events

``MultiIcecastEvent`` provides per-destination and aggregate events:

| Event | Description |
|-------|-------------|
| `.destinationConnected(label:serverVersion:)` | A destination connected |
| `.destinationDisconnected(label:error:)` | A destination disconnected |
| `.destinationReconnecting(label:attempt:)` | A destination is reconnecting |
| `.destinationReconnected(label:)` | A destination reconnected |
| `.allConnected` | All destinations are connected |
| `.sendComplete(successCount:failureCount:)` | Send result across destinations |
| `.destinationAdded(label:)` | A destination was added |
| `.destinationRemoved(label:)` | A destination was removed |
| `.metadataUpdated(label:)` | Metadata updated on a destination |

```swift
for await event in multi.events {
    switch event {
    case .destinationConnected(let label, _):
        print("\(label) connected")
    case .destinationDisconnected(let label, let error):
        print("\(label) disconnected: \(error?.localizedDescription ?? "clean")")
    case .allConnected:
        print("All destinations online")
    default:
        break
    }
}
```

### Statistics

``MultiIcecastStatistics`` provides both per-destination and aggregated statistics:

```swift
let stats = await multi.statistics

// Per-destination
for (label, destStats) in stats.perDestination {
    print("\(label): \(destStats.bytesSent) bytes")
}

// Aggregated
print("Total bytes: \(stats.aggregated.bytesSent)")
print("Connected: \(stats.connectedCount)/\(stats.totalCount)")
print("Reconnecting: \(stats.reconnectingCount)")
```

### Metadata

Update metadata on all connected destinations:

```swift
let metadata = ICYMetadata(streamTitle: "Artist - Song")
await multi.updateMetadata(metadata)
```

Disconnected destinations are skipped without error.

### Destination Inspection

List current destinations with their state:

```swift
let destinations = await multi.destinations
for dest in destinations {
    print("\(dest.label): \(dest.state), \(dest.configuration.host)")
}
```

### CLI Usage

The `icecast-cli stream` command supports multi-destination via `--dest`:

```bash
icecast-cli stream audio.mp3 \
    --dest "primary:radio1.example.com:8000:/live.mp3:secret1" \
    --dest "backup:backup.example.com:8000:/live.mp3:secret2"
```

## Next Steps

- <doc:StreamingGuide> — Single-destination streaming workflow
- <doc:MetricsExportGuide> — Per-destination metrics with automatic labels
- <doc:MonitoringGuide> — Connection events and statistics
