# SHOUTcast Compatibility

Stream audio using SHOUTcast v1 and v2 protocols.

@Metadata {
    @PageKind(article)
}

## Overview

IcecastKit supports both SHOUTcast v1 (password-only) and SHOUTcast v2 (multi-stream with stream IDs). This guide explains the protocol differences, configuration, credential formats, and port handling.

### SHOUTcast v1

SHOUTcast v1 uses a simple password-only authentication:

1. Connect to the **source port** (listener port + 1)
2. Send the password line: `password\r\n`
3. Server responds with `OK2` and optional `icy-caps:N`
4. Send stream headers (`content-type`, `icy-name`, etc.)
5. Begin streaming audio data

```swift
let configuration = IcecastConfiguration(
    host: "shoutcast.example.com",
    port: 8000,
    mountpoint: "/stream",
    stationInfo: StationInfo(name: "SHOUTcast Radio", genre: "Jazz", bitrate: 128),
    protocolMode: .shoutcastV1
)
let credentials = IcecastCredentials.shoutcast(password: "shoutpass")

let client = IcecastClient(
    configuration: configuration,
    credentials: credentials
)
try await client.connect()
```

### SHOUTcast v2

SHOUTcast v2 extends v1 with multi-stream support via stream IDs. The password format is `password:#streamId`:

```swift
let configuration = IcecastConfiguration(
    host: "shoutcast.example.com",
    port: 8000,
    mountpoint: "/stream",
    stationInfo: StationInfo(name: "SHOUTcast v2 Radio", bitrate: 192),
    protocolMode: .shoutcastV2(streamId: 3)
)
let credentials = IcecastCredentials.shoutcast(password: "v2pass")

let client = IcecastClient(
    configuration: configuration,
    credentials: credentials
)
try await client.connect()
// Password sent as: "v2pass:#3\r\n"
```

### Configuration

Use ``ProtocolMode/shoutcastV1`` or ``ProtocolMode/shoutcastV2(streamId:)`` to select the protocol:

| Mode | Password Format | Use Case |
|------|----------------|----------|
| `.shoutcastV1` | `password\r\n` | Single-stream SHOUTcast servers |
| `.shoutcastV2(streamId: N)` | `password:#N\r\n` | Multi-stream SHOUTcast DNAS servers |

### Credentials

Use the factory methods on ``IcecastCredentials`` for SHOUTcast:

```swift
// SHOUTcast v1 — password only, no username
let v1Creds = IcecastCredentials.shoutcast(password: "mypass")

// SHOUTcast v2 — password with stream ID
let v2Creds = IcecastCredentials.shoutcastV2(password: "mypass", streamId: 3)
```

For URL-based configuration, use the `shoutcast://` scheme:

```swift
// SHOUTcast v1
let (config, creds) = try IcecastConfiguration.from(
    url: "shoutcast://mypass@shoutcast.example.com:8000/stream"
)

// SHOUTcast v2 with stream ID
let (config2, creds2) = try IcecastConfiguration.from(
    url: "shoutcast://mypass@shoutcast.example.com:8000/stream?streamId=3"
)
```

### Port Handling

SHOUTcast uses a **source port** that is the listener port plus one. IcecastKit handles this automatically when the protocol mode is `.shoutcastV1` or `.shoutcastV2`:

| Configured Port | Actual Connection Port |
|-----------------|----------------------|
| `8000` | `8001` (source port) |
| `9000` | `9001` (source port) |

You configure the **listener port** (the one users connect to for playback). IcecastKit internally adds 1 for the source connection.

### Limitations

SHOUTcast differs from Icecast in several ways:

| Feature | Icecast | SHOUTcast |
|---------|---------|-----------|
| Admin API | Full support (metadata, stats) | Not available |
| Metadata method | Admin API or inline | Inline only |
| Protocol negotiation | PUT with SOURCE fallback | Fixed v1/v2 |
| Mountpoints | Multiple, independent | Single or stream-ID based |
| TLS | Supported | Depends on server |

## Next Steps

- <doc:StreamingGuide> — Complete connection lifecycle
- <doc:MetadataGuide> — ICY metadata encoding for SHOUTcast
- <doc:CLIReference> — CLI streaming with `--protocol shoutcast-v1`
