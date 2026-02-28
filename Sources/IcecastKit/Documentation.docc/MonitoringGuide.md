# Monitoring Guide

Observe connection events, track statistics, and measure bitrate in real time.

@Metadata {
    @PageKind(article)
}

## Overview

IcecastKit provides real-time connection monitoring through ``ConnectionMonitor``, which acts as the central event bus. All events flow through an `AsyncStream` that you can iterate over to react to state changes, errors, metadata updates, and periodic statistics.

### Connection Events

``ConnectionEvent`` has seven cases covering the full lifecycle:

| Event | Description |
|-------|-------------|
| `.connected(host:port:mountpoint:protocolName:)` | Successfully connected to the server |
| `.disconnected(reason:)` | Disconnected (with ``DisconnectReason``) |
| `.reconnecting(attempt:delay:)` | Attempting to reconnect |
| `.metadataUpdated(_:method:)` | Metadata was updated (via ``MetadataUpdateMethod``) |
| `.error(_:)` | An ``IcecastError`` occurred |
| `.statistics(_:)` | Periodic ``ConnectionStatistics`` snapshot |
| `.protocolNegotiated(_:)` | Protocol was successfully negotiated |

### Consuming Events

Iterate over the ``IcecastClient/events`` `AsyncStream` to receive events:

```swift
let client = IcecastClient(
    configuration: configuration,
    credentials: credentials
)

// Consume events in a background task
let eventTask = Task {
    for await event in client.events {
        switch event {
        case .connected(let host, let port, let mountpoint, let protocolName):
            print("Connected to \(host):\(port)\(mountpoint) via \(protocolName)")
        case .disconnected(let reason):
            print("Disconnected: \(reason)")
        case .reconnecting(let attempt, let delay):
            print("Reconnecting (attempt \(attempt), delay \(delay)s)")
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
// Events flow through the stream...

await client.disconnect()
eventTask.cancel()
```

### ConnectionMonitor

For advanced use, access the monitor directly via ``IcecastClient/monitor``:

```swift
let monitor = client.monitor

// Read current statistics
let stats = await monitor.statistics

// Access the event stream
for await event in monitor.events {
    // ...
}
```

The monitor initializes with a configurable statistics emission interval (default 5.0 seconds):

```swift
let monitor = ConnectionMonitor(statisticsInterval: 10.0)
```

Pass `nil` to disable periodic statistics emission.

### Connection Statistics

``ConnectionStatistics`` provides a snapshot of the current session:

| Property | Type | Description |
|----------|------|-------------|
| `bytesSent` | `UInt64` | Total audio bytes sent |
| `bytesTotal` | `UInt64` | Total bytes including overhead |
| `duration` | `TimeInterval` | Streaming duration in seconds |
| `averageBitrate` | `Double` | Average bitrate since connection (bps) |
| `currentBitrate` | `Double` | Current bitrate from rolling window (bps) |
| `metadataUpdateCount` | `Int` | Number of metadata updates |
| `reconnectionCount` | `Int` | Number of successful reconnections |
| `connectedSince` | `Date?` | When the current connection was established |
| `sendErrorCount` | `Int` | Number of send errors |

```swift
try await client.connect()
try await client.send(audioData)

let stats = await client.statistics
print("Sent: \(stats.bytesSent) bytes")
print("Duration: \(stats.duration)s")
print("Bitrate: \(stats.currentBitrate) bps")
```

The `connectedSince` property is set when connecting and cleared on disconnect:

```swift
let before = await client.statistics
// before.connectedSince == nil

try await client.connect()
let during = await client.statistics
// during.connectedSince != nil

await client.disconnect()
let after = await client.statistics
// after.connectedSince == nil
```

### Periodic Statistics

When `statisticsInterval` is set (default 5.0 seconds), the monitor automatically emits ``ConnectionEvent/statistics(_:)`` events at that interval while connected. These provide a real-time view of streaming health:

```swift
for await event in client.events {
    if case .statistics(let stats) = event {
        print("Bitrate: \(stats.currentBitrate / 1000) kbps")
        print("Total: \(stats.bytesSent) bytes")
    }
}
```

Current bitrate is computed from a 5-second rolling window for responsiveness.

### Disconnect Reasons

``DisconnectReason`` explains why a disconnection occurred:

| Reason | Description |
|--------|-------------|
| `.requested` | Client called `disconnect()` |
| `.serverClosed` | Server closed the connection |
| `.networkError(_)` | A network error occurred |
| `.authenticationFailed` | Server rejected credentials |
| `.mountpointInUse` | Mountpoint is taken by another source |
| `.maxRetriesExceeded` | Reconnection attempts exhausted |
| `.contentTypeRejected` | Server rejected the content type |

## Next Steps

- <doc:ReconnectionGuide> — Auto-reconnect configuration
- <doc:StreamingGuide> — Connection lifecycle and state machine
- <doc:MetadataGuide> — Metadata update events
