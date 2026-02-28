# Getting Started with IcecastKit

Set up your first Icecast audio stream in minutes.

## Overview

IcecastKit provides everything you need to stream audio to Icecast and SHOUTcast servers from Swift. This guide walks you through installation, basic configuration, and your first streaming session.

### Installation

Add IcecastKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/atelier-socle/swift-icecast-kit.git", from: "0.1.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["IcecastKit"]
)
```

### Import

```swift
import IcecastKit
```

### Quick Start

The minimal setup to connect and stream audio:

```swift
// 1. Configure the server connection
let configuration = IcecastConfiguration(
    host: "radio.example.com",
    port: 8000,
    mountpoint: "/live.mp3"
)

// 2. Set up authentication
let credentials = IcecastCredentials(password: "hackme")

// 3. Create the client
let client = IcecastClient(
    configuration: configuration,
    credentials: credentials
)

// 4. Connect to the server
try await client.connect()

// 5. Send audio data
try await client.send(audioData)

// 6. Update metadata (optional)
try await client.updateMetadata(ICYMetadata(streamTitle: "Artist - Song"))

// 7. Disconnect when done
await client.disconnect()
```

### URL-Based Configuration

For convenience, you can create a configuration from a URL string:

```swift
let (config, creds) = try IcecastConfiguration.from(
    url: "icecast://source:hackme@radio.example.com:8000/live.mp3"
)
let client = IcecastClient(configuration: config, credentials: creds)
```

Supported URL schemes:

| Scheme | Protocol |
|--------|----------|
| `icecast://` | Auto-detect (PUT or SOURCE) |
| `shoutcast://` | SHOUTcast v1 (or v2 with `?streamId=N`) |
| `http://` | Auto-detect |
| `https://` | Auto-detect with TLS |

### Content Type Detection

IcecastKit can auto-detect the audio content type from a filename:

```swift
let contentType = AudioContentType.detect(from: "music.mp3")
// Returns .mp3 (audio/mpeg)
```

Supported formats:

| Extension | Content Type |
|-----------|-------------|
| `.mp3` | `audio/mpeg` |
| `.aac`, `.m4a` | `audio/aac` |
| `.ogg`, `.oga` | `application/ogg` |
| `.opus` | `audio/ogg` |

## Next Steps

- <doc:StreamingGuide> — Complete streaming configuration and lifecycle
- <doc:MetadataGuide> — ICY metadata encoding and admin API
- <doc:ReconnectionGuide> — Auto-reconnect with exponential backoff
