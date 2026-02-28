# swift-icecast-kit

[![CI](https://github.com/atelier-socle/swift-icecast-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/atelier-socle/swift-icecast-kit/actions/workflows/ci.yml)
[![codecov](https://codecov.io/github/atelier-socle/swift-icecast-kit/graph/badge.svg)](https://codecov.io/github/atelier-socle/swift-icecast-kit)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20|%20iOS%20|%20tvOS%20|%20watchOS%20|%20visionOS%20|%20Linux-blue.svg)]()
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

<!-- ![swift-icecast-kit](./assets/banner.png) -->

A pure Swift client library for streaming audio to Icecast and SHOUTcast servers. Supports Icecast HTTP PUT (modern), Icecast SOURCE (legacy), and SHOUTcast v1/v2 protocols. Cross-platform TCP transport with Network.framework on Apple platforms and POSIX sockets on Linux. Strict `Sendable` conformance throughout. Zero external dependencies in the core library (only `swift-argument-parser` for the CLI).

Part of the [Atelier Socle](https://www.atelier-socle.com) ecosystem.

---

## Features

- **Icecast HTTP PUT** — Modern Icecast 2.4+ streaming with `Expect: 100-continue`
- **Icecast SOURCE** — Legacy Icecast protocol for older servers
- **SHOUTcast v1/v2** — SHOUTcast password authentication and ICY headers
- **Auto-negotiation** — Automatic protocol detection with graceful fallback
- **Cross-platform transport** — Network.framework (Apple) / POSIX sockets (Linux)
- **TLS support** — Secure streaming on Apple platforms
- **ICY metadata** — In-stream metadata updates (song title, artist, URL)
- **Admin API** — Server-side metadata updates via Icecast admin endpoints
- **Connection monitoring** — Health checks, reconnection, and statistics
- **Strict concurrency** — All public types are `Sendable`, built with Swift 6.2
- **Zero dependencies** — Core library has no third-party dependencies
- **CLI tool** — `icecast-cli` for streaming, testing connections, and server info

---

## Installation

### Requirements

- **Swift 6.2+** with strict concurrency
- **Library platforms**: macOS 14+, iOS 17+, tvOS 17+, watchOS 10+, visionOS 1+
- **CLI platforms**: macOS 14+, Linux
- **Zero third-party dependencies** in the core library (`swift-argument-parser` for CLI only)

### Swift Package Manager

Add the dependency to your `Package.swift`:

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

### Homebrew

```bash
brew install atelier-socle/tools/swift-icecast-kit
```

### Manual Installation

```bash
git clone https://github.com/atelier-socle/swift-icecast-kit.git
cd swift-icecast-kit
./Scripts/install.sh
```

---

## Quick Start

```swift
import IcecastKit

// Configure credentials and station info
let credentials = IcecastCredentials(password: "hackme")
let station = StationInfo(
    name: "My Radio Station",
    description: "The best radio in town",
    genre: "Rock;Alternative",
    isPublic: true,
    bitrate: 128,
    sampleRate: 44100,
    channels: 2
)

// Build an Icecast PUT request
let builder = HTTPRequestBuilder()
let request = builder.buildIcecastPUT(
    mountpoint: "/live.mp3",
    credentials: credentials,
    host: "radio.example.com",
    port: 8000,
    contentType: .mp3,
    stationInfo: station
)
```

---

## CLI

### Installation

```bash
swift build -c release
cp .build/release/icecast-cli /usr/local/bin/
```

### Usage

```bash
# Test connection to an Icecast server
icecast-cli test-connection --host radio.example.com --port 8000

# Stream an audio file
icecast-cli stream --host radio.example.com --mount /live.mp3 --file audio.mp3

# Get server info
icecast-cli info --host radio.example.com --port 8000
```

### Commands

| Command | Description |
|---------|-------------|
| `stream` | Stream audio data to an Icecast/SHOUTcast server |
| `test-connection` | Test connectivity to a streaming server |
| `info` | Display server and mountpoint information |

---

## Architecture

```
Sources/
├── IcecastKit/                  # Core library (zero dependencies)
│   ├── Client/                  # Credentials, configuration, protocol mode
│   ├── Protocol/                # HTTP request builder, response parser
│   ├── Metadata/                # ICY metadata, admin API
│   ├── Transport/               # TCP transport (NWConnection / POSIX)
│   ├── Monitoring/              # Connection health, statistics
│   ├── Errors/                  # Typed error hierarchy
│   └── Extensions/              # Data + String helpers
├── IcecastKitCommands/          # CLI command implementations
└── IcecastKitCLI/               # CLI entry point (@main)
```

---

## Documentation

Full API documentation is available as a DocC catalog bundled with the package. Open the project in Xcode and select **Product > Build Documentation** to browse it locally.

---

## Specification References

- [Icecast Protocol Documentation](https://icecast.org/docs/)
- [SHOUTcast Protocol (ICY)](https://cast.readme.io/docs)
- [RFC 7230 — HTTP/1.1 Message Syntax](https://datatracker.ietf.org/doc/html/rfc7230)
- [ICY Metadata Specification](https://cast.readme.io/docs/icy)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute.

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).

Copyright 2026 [Atelier Socle SAS](https://www.atelier-socle.com). See [NOTICE](NOTICE) for details.
