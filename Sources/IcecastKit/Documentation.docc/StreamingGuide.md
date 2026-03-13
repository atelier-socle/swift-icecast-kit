# Streaming Guide

Configure connections, negotiate protocols, and stream audio data.

@Metadata {
    @PageKind(article)
}

## Overview

This guide covers the complete streaming workflow: configuring the server connection, setting up station metadata, selecting a protocol, and managing the connection lifecycle. All code examples are verified against the actual IcecastKit API.

### Configuration

``IcecastConfiguration`` holds all parameters for connecting to a server:

```swift
let configuration = IcecastConfiguration(
    host: "radio.example.com",
    port: 8000,
    mountpoint: "/live.mp3",
    useTLS: false,
    contentType: .mp3,
    stationInfo: stationInfo,
    protocolMode: .auto,
    adminCredentials: nil,
    metadataInterval: 8192
)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `host` | `String` | (required) | Server hostname |
| `port` | `Int` | `8000` | Server port |
| `mountpoint` | `String` | (required) | Mountpoint path (e.g., `"/live.mp3"`) |
| `useTLS` | `Bool` | `false` | Enable TLS encryption |
| `contentType` | ``AudioContentType`` | `.mp3` | Audio MIME type |
| `stationInfo` | ``StationInfo`` | `StationInfo()` | Station metadata for headers |
| `protocolMode` | ``ProtocolMode`` | `.auto` | Protocol variant |
| `adminCredentials` | ``IcecastCredentials``? | `nil` | Admin API credentials |
| `metadataInterval` | `Int` | `8192` | Metadata interval in bytes |

### Station Info

``StationInfo`` provides radio station metadata sent as `ice-*` (Icecast) or `icy-*` (SHOUTcast) headers during the handshake:

```swift
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
```

The `audioInfoHeaderValue()` method builds the `ice-audio-info` header:

```swift
let audioInfo = stationInfo.audioInfoHeaderValue()
// "ice-channels=2;ice-samplerate=44100;ice-bitrate=128"
```

### Protocol Modes

IcecastKit supports five protocol modes via ``ProtocolMode``:

| Mode | Description |
|------|-------------|
| `.auto` | Try PUT first, fall back to SOURCE (recommended) |
| `.icecastPUT` | Modern Icecast 2.4+ HTTP PUT |
| `.icecastSOURCE` | Legacy Icecast SOURCE for pre-2.4.0 servers |
| `.shoutcastV1` | SHOUTcast v1 password authentication |
| `.shoutcastV2(streamId:)` | SHOUTcast v2 with stream ID |

With `.auto` mode, ``ProtocolNegotiator`` tries PUT first. If the server returns an empty response (indicating a pre-2.4.0 server), the negotiator closes the connection, opens a new one, and tries SOURCE.

### Connection Lifecycle

``IcecastClient`` follows a state machine managed by ``ConnectionState``:

```
disconnected --> connecting --> authenticating --> connected --> streaming
     ^                                                |
     <------------ reconnecting <---------------------+
     ^                                                |
     <------------ failed <---------------------------+
```

**States:**

| State | Description |
|-------|-------------|
| `.disconnected` | Not connected |
| `.connecting` | TCP connection in progress |
| `.authenticating` | Protocol handshake in progress |
| `.connected` | Ready to send audio data |
| `.streaming` | Actively sending audio data |
| `.reconnecting(attempt:nextRetryIn:)` | Reconnecting after loss |
| `.failed(_)` | Connection failed with error |

```swift
let client = IcecastClient(
    configuration: configuration,
    credentials: IcecastCredentials(password: "hackme")
)

try await client.connect()
// state == .connected

try await client.send(audioData)
// state == .streaming

await client.disconnect()
// state == .disconnected
```

### Sending Data

The ``IcecastClient/send(_:)`` method sends audio data to the server. On the first call after connecting, the state transitions from `.connected` to `.streaming`.

IcecastKit does **not** enforce pacing — it is the caller's responsibility to send data at the correct bitrate. For example, for 128 kbps MP3:

```swift
let chunkSize = 4096
let chunkCount = 480_000 / chunkSize  // ~30s of 128 kbps audio

for _ in 0..<chunkCount {
    try await client.send(Data(repeating: 0xFF, count: chunkSize))
}
```

### Sending Raw AAC with ADTS Wrapping

If your audio pipeline produces raw AAC access units (without ADTS headers), use ``IcecastClient/send(rawAAC:audioConfiguration:)`` to let IcecastKit wrap each frame automatically per ISO 13818-7:

```swift
let audioConfig = AudioConfiguration(sampleRate: 44100, channelCount: 2)

// Each call wraps the raw AAC data in a 7-byte ADTS header before sending
try await client.send(rawAAC: rawAACFrame, audioConfiguration: audioConfig)
```

The ``AudioConfiguration`` struct describes the audio format (sample rate, channel count, AAC profile). The ``AACProfile`` enum supports `.main`, `.lc` (default), `.ssr`, and `.ltp`.

If your data already has ADTS headers (e.g., from an AAC file), use the regular ``IcecastClient/send(_:)`` method instead.

### Disconnection

``IcecastClient/disconnect()`` gracefully closes the connection. It is safe to call in any state (idempotent):

```swift
await client.disconnect()
// state == .disconnected
```

Disconnecting during reconnection cancels the reconnection loop immediately.

### Runtime Updates

You can update the configuration and reconnect policy at runtime without disconnecting:

```swift
await client.updateConfiguration(
    IcecastConfiguration(host: "new.host.com", mountpoint: "/new.mp3")
)

await client.updateReconnectPolicy(.aggressive)
```

Configuration changes take effect on the next connection attempt.

## Next Steps

- <doc:MetadataGuide> — ICY metadata and admin API
- <doc:ShoutcastCompatibility> — SHOUTcast v1/v2 protocol details
- <doc:ReconnectionGuide> — Auto-reconnect configuration
