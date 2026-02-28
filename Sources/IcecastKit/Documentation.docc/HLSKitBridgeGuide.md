# HLSKit Bridge Guide

Integrate IcecastKit with HLSKit using the bridge pattern.

@Metadata {
    @PageKind(article)
}

## Overview

IcecastKit has **no dependency on [HLSKit](https://github.com/atelier-socle/swift-hls-kit)**. The bridge conformance is implemented in the consuming app or a dedicated glue package that imports both `IcecastKit` and `HLSKit`. This keeps each library independent and composable.

### Design Philosophy

The Atelier Socle streaming ecosystem follows a strict separation of concerns:

- **IcecastKit** — Icecast/SHOUTcast streaming (this library)
- **swift-rtmp-kit** — RTMP publish client (planned)
- **swift-srt-kit** — SRT library (planned)
- **swift-hls-kit** — HLS manifest and live streaming

Each transport library is a standalone package with zero cross-dependencies. Integration happens at the **application layer** through protocol conformance.

### Bridge Pattern

HLSKit defines an `IcecastTransport` protocol for push-based streaming. Your app or glue package provides the conformance:

```swift
// In your app or glue package that imports both IcecastKit and HLSKit:

import IcecastKit
import HLSKit

/// Bridge conforming IcecastClient to HLSKit's IcecastTransport protocol.
extension IcecastClient: IcecastTransport {
    public func connect(
        to url: String,
        credentials: HLSKit.IcecastCredentials,
        mountpoint: String
    ) async throws {
        let (config, _) = try IcecastConfiguration.from(url: url)
        var updatedConfig = config
        updatedConfig.mountpoint = mountpoint
        await self.updateConfiguration(updatedConfig)
        try await self.connect()
    }

    public func updateMetadata(_ metadata: HLSKit.IcecastMetadata) async throws {
        let icyMetadata = ICYMetadata(
            streamTitle: metadata.title,
            streamUrl: metadata.url
        )
        try await self.updateMetadata(icyMetadata)
    }
}
```

### Transport Dependency Injection

All three transport libraries (icecast, rtmp, srt) follow the same pattern:

1. Each library defines its own client actor with `connect()`, `send()`, `disconnect()`
2. HLSKit defines a transport protocol for each push target
3. The consuming app or glue package bridges the two with an extension conformance
4. HLSKit's `LivePipeline` accepts any conforming transport

This means you can swap transport implementations without modifying either library.

### Usage in HLSKit LivePipeline

Once the bridge conformance is in place, HLSKit's live pipeline can use IcecastKit directly:

```swift
import HLSKit
import IcecastKit

// Create the Icecast client
let icecastClient = IcecastClient(
    configuration: IcecastConfiguration(host: "radio.example.com", mountpoint: "/live.mp3"),
    credentials: IcecastCredentials(password: "hackme")
)

// Pass it to the live pipeline as the push transport
let pipeline = LivePipeline(transport: icecastClient)
try await pipeline.start()
```

The pipeline manages the connection lifecycle and forwards encoded audio segments to the Icecast server.

## Next Steps

- <doc:StreamingGuide> — IcecastKit connection lifecycle
- <doc:GettingStarted> — Quick start with IcecastKit standalone
- <doc:MonitoringGuide> — Monitor the transport connection health
