# Bandwidth Probing

Measure upload bandwidth and latency before starting a stream.

@Metadata {
    @PageKind(article)
}

## Overview

``IcecastBandwidthProbe`` connects to an Icecast server and sends test data to measure real-world upload performance. The result helps you choose the optimal bitrate before committing to a live stream.

### Running a Probe

```swift
let probe = IcecastBandwidthProbe()
let result = try await probe.measure(
    host: "radio.example.com",
    port: 8000,
    mountpoint: "/probe",
    credentials: IcecastCredentials(password: "hackme"),
    contentType: .mp3,
    duration: 5.0
)

print("Bandwidth: \(result.uploadBandwidth) bps")
print("Latency: \(result.averageWriteLatency) ms")
print("Stability: \(result.stabilityScore)/100")
print("Recommended: \(result.recommendedBitrate) bps")
```

The probe connects, performs the handshake, sends dummy audio data for the specified duration, then disconnects and returns the measurements.

### Probe Result

``IcecastProbeResult`` contains all measured values:

| Property | Type | Description |
|----------|------|-------------|
| `uploadBandwidth` | `Double` | Measured upload bandwidth (bps) |
| `averageWriteLatency` | `Double` | Average write latency (ms) |
| `writeLatencyVariance` | `Double` | Latency variance (ms²) |
| `stabilityScore` | `Double` | Connection stability 0–100 |
| `recommendedBitrate` | `Int` | Suggested bitrate based on measurements |
| `latencyClass` | ``IcecastProbeResult/LatencyClass`` | Latency classification |
| `duration` | `TimeInterval` | Actual probe duration |
| `serverVersion` | `String?` | Server version from response headers |

### Latency Classification

``IcecastProbeResult/LatencyClass`` classifies the measured latency:

| Class | Threshold | Description |
|-------|-----------|-------------|
| `.low` | < 50 ms | Excellent for high-bitrate streaming |
| `.medium` | 50–200 ms | Suitable for standard streaming |
| `.high` | > 200 ms | May require lower bitrate |

```swift
let latencyClass = IcecastProbeResult.LatencyClass.classify(10)  // .low
let medium = IcecastProbeResult.LatencyClass.classify(100)       // .medium
let high = IcecastProbeResult.LatencyClass.classify(300)         // .high
```

### Target Quality

``ProbeTargetQuality`` controls how aggressively the probe recommends bitrate relative to measured bandwidth:

| Quality | Utilization Factor | Description |
|---------|-------------------|-------------|
| `.quality` | 0.95 | Use 95% of bandwidth — maximizes audio quality |
| `.balanced` | 0.85 | Use 85% — headroom for network variance |
| `.lowLatency` | 0.70 | Use 70% — generous headroom for stability |

### Auto-Configuration from Probe

Use ``IcecastConfiguration/from(url:)`` to parse a URL into a ready-to-use configuration:

```swift
let (config, creds) = try IcecastConfiguration.from(
    url: "icecast://source:hackme@radio.example.com:8000/live.mp3"
)
```

Supported URL schemes:

| Scheme | Protocol Mode |
|--------|--------------|
| `icecast://` | `.auto` (PUT/SOURCE) |
| `shoutcast://` | `.shoutcastV1` |
| `http://` | `.auto` |
| `https://` | `.auto` with TLS |

### Content-Aware Recommendations

The probe recommends bitrates from format-specific ``AudioQualityStep`` tiers:

```swift
// Probe with AAC content type → recommends from AAC quality steps
let result = try await probe.measure(
    host: "radio.example.com",
    mountpoint: "/probe",
    credentials: IcecastCredentials(password: "test"),
    contentType: .aac,
    duration: 2.0
)
let validBitrates = AudioQualityStep.aacSteps.map(\.bitrate)
// result.recommendedBitrate is one of the valid AAC bitrates
```

### CLI Usage

The `icecast-cli probe` command runs a bandwidth probe from the command line:

```bash
icecast-cli probe --host radio.example.com --port 8000 \
    --password hackme \
    --duration 10 \
    --content-type mp3
```

## Next Steps

- <doc:AdaptiveBitrateGuide> — Real-time bitrate adaptation during streaming
- <doc:ConnectionQualityGuide> — Quality scoring and health monitoring
- <doc:StreamingGuide> — Connection lifecycle and streaming
