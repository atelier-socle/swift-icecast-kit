# Metadata Guide

Encode ICY metadata, interleave it into streams, and update metadata via the admin API.

@Metadata {
    @PageKind(article)
}

## Overview

IcecastKit provides complete support for ICY stream metadata — the protocol used by Icecast and SHOUTcast to embed song titles and other information in audio streams. This guide covers the metadata model, binary encoding, stream interleaving, and the admin API for server-side updates.

### ICY Metadata Model

``ICYMetadata`` represents stream metadata with three fields:

```swift
let metadata = ICYMetadata(
    streamTitle: "Artist - Song Title",
    streamUrl: "https://example.com",
    customFields: ["CustomKey": "value"]
)
```

| Property | Type | Description |
|----------|------|-------------|
| `streamTitle` | `String?` | The stream title (universally supported by players) |
| `streamUrl` | `String?` | Optional stream URL (inconsistent player support) |
| `customFields` | `[String: String]` | Additional custom metadata fields |

Use `isEmpty` to check if a metadata value contains no fields, and `urlEncodedSong()` to get a percent-encoded title for the admin API.

### Encoding

``ICYMetadataEncoder`` converts metadata into the binary wire format:

```swift
let encoder = ICYMetadataEncoder()
let encoded = try encoder.encode(metadata)
```

**Wire format:**
- Byte 0: length indicator `N` (unsigned). Actual metadata length = N x 16.
- Bytes 1...: metadata string zero-padded to N x 16 bytes.

The string format is `key='value';` pairs: `StreamTitle='Artist - Song';StreamUrl='https://example.com';`

Single quotes inside values are escaped with backslash (`\'`). The maximum payload size is 4,080 bytes (255 x 16).

Use `encodeString(_:)` to get the string representation without binary framing, or `encodeEmpty()` for an empty metadata block (single `0x00` byte).

### Decoding

``ICYMetadataDecoder`` parses the binary wire format back into ``ICYMetadata``:

```swift
let decoder = ICYMetadataDecoder()
let (decoded, bytesConsumed) = try decoder.decode(from: encodedData)
// decoded.streamTitle == "Artist - Song Title"
// bytesConsumed == 1 + N * 16
```

The decoder handles escaped single quotes and stores unrecognized keys in `customFields`. Use `parse(string:)` to parse a metadata string directly without binary framing.

### Metadata Interleaving

``MetadataInterleaver`` inserts metadata blocks into an audio stream at fixed byte intervals (the `metaint` value):

```swift
let interleaver = MetadataInterleaver(metaint: 8192)

// Set the current metadata
await interleaver.updateMetadata(ICYMetadata(streamTitle: "Artist - Song"))

// Process audio data — metadata blocks are inserted automatically
let output = try await interleaver.interleave(audioData)
```

The interleaver tracks its byte position across multiple calls, so you can feed audio data in any chunk size. The output stream looks like:

```
[audio: 8192 bytes] [metadata block] [audio: 8192 bytes] [metadata block] ...
```

Pass `nil` to `updateMetadata(_:)` to clear metadata. Empty metadata blocks (single `0x00` byte) are inserted at each interval.

### Admin API Metadata Updates

The preferred method for updating stream metadata is via the Icecast admin HTTP API. ``AdminMetadataClient`` sends `GET /admin/metadata?mount=...&mode=updinfo&song=...` requests:

```swift
let adminClient = AdminMetadataClient(
    host: "radio.example.com",
    port: 8000,
    useTLS: false,
    credentials: IcecastCredentials(username: "admin", password: "adminpass")
)

let metadata = ICYMetadata(streamTitle: "Test & Title")
try await adminClient.updateMetadata(metadata, mountpoint: "/live.mp3")
```

The admin client uses a separate TCP connection from the source stream. The `song` parameter is URL-encoded (spaces become `+`, special characters are percent-encoded).

### Client Metadata Updates

``IcecastClient/updateMetadata(_:)`` automatically selects the best method:

1. If `adminCredentials` are configured on ``IcecastConfiguration``, it uses the admin API.
2. If the admin API returns a 404 (unavailable), it falls back to inline metadata.
3. If no admin credentials are set, it stores metadata for inline interleaving.

```swift
let config = IcecastConfiguration(
    host: "radio.example.com",
    mountpoint: "/live.mp3",
    adminCredentials: IcecastCredentials(username: "admin", password: "adminpass")
)
let client = IcecastClient(configuration: config, credentials: credentials)
try await client.connect()

// Automatically uses admin API, falls back to inline if unavailable
try await client.updateMetadata(ICYMetadata(streamTitle: "Admin Song"))
```

Each update emits a ``ConnectionEvent/metadataUpdated(_:method:)`` event indicating whether ``MetadataUpdateMethod/adminAPI`` or ``MetadataUpdateMethod/inline`` was used.

### Server Statistics

``AdminMetadataClient`` also provides access to Icecast server statistics:

```swift
// Global server stats
let serverStats = try await adminClient.fetchServerStats()
// serverStats.serverVersion — e.g., "Icecast 2.5.0"
// serverStats.activeMountpoints — ["/live.mp3", "/ambient.ogg"]
// serverStats.totalListeners — 57
// serverStats.totalSources — 2

// Mountpoint-specific stats
let mountStats = try await adminClient.fetchMountStats(mountpoint: "/live.mp3")
// mountStats.listeners — 42
// mountStats.streamTitle — "Live Stream"
// mountStats.bitrate — 128
// mountStats.genre — "Rock"
// mountStats.contentType — "audio/mpeg"
// mountStats.connectedDuration — 3600
```

## Next Steps

- <doc:StreamingGuide> — Connection lifecycle and sending audio data
- <doc:ShoutcastCompatibility> — SHOUTcast v1/v2 metadata differences
- <doc:MonitoringGuide> — Tracking metadata update events
