# Adaptive Bitrate

Automatically adjust streaming bitrate based on real-time network conditions.

@Metadata {
    @PageKind(article)
}

## Overview

IcecastKit includes a complete adaptive bitrate (ABR) system that monitors network conditions and recommends bitrate adjustments in real time. The system uses EWMA (Exponentially Weighted Moving Average) smoothing to detect congestion, RTT spikes, and bandwidth slowdowns — then recommends bitrate changes with configurable policies.

### Policies

``AdaptiveBitratePolicy`` defines how aggressively the system reacts to network changes:

| Policy | Step Down | Step Up | Hysteresis | Behavior |
|--------|-----------|---------|------------|----------|
| `.conservative` | 0.75× | 1.10× | 5 signals | Slow to reduce, slow to recover |
| `.responsive` | 0.75× | 1.10× | 3 signals | Balanced reaction speed |
| `.aggressive` | 0.50× | 1.50× | 1 signal | Fast reduction, fast recovery |
| `.custom(_)` | configurable | configurable | configurable | Full control |

Convenience constructors let you override the min/max bitrate bounds while keeping other defaults:

```swift
let policy = AdaptiveBitratePolicy.conservative(min: 64_000, max: 192_000)
```

### Configuration

``AdaptiveBitrateConfiguration`` controls the ABR engine parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `minBitrate` | `Int` | 32,000 | Floor bitrate (bps) |
| `maxBitrate` | `Int` | 320,000 | Ceiling bitrate (bps) |
| `stepDown` | `Double` | 0.75 | Multiplier on reduction |
| `stepUp` | `Double` | 1.10 | Multiplier on recovery |
| `downTriggerThreshold` | `Double` | 1.3 | EWMA latency ratio to trigger reduction |
| `upStabilityDuration` | `Double` | 15.0 | Seconds of stability before recovery |
| `measurementWindow` | `Double` | 5.0 | Rolling window for measurements |
| `hysteresisCount` | `Int` | 3 | Congestion signals before action |

```swift
let config = AdaptiveBitrateConfiguration(
    minBitrate: 64_000,
    maxBitrate: 192_000,
    stepDown: 0.80,
    stepUp: 1.10,
    downTriggerThreshold: 1.3,
    upStabilityDuration: 0.0,
    measurementWindow: 0.0,
    hysteresisCount: 1
)
let policy = AdaptiveBitratePolicy.custom(config)
```

### Network Condition Monitor

``NetworkConditionMonitor`` is the actor that drives ABR. It records write measurements and emits ``BitrateRecommendation`` values through an `AsyncStream`:

```swift
let monitor = NetworkConditionMonitor(
    policy: .conservative,
    currentBitrate: 128_000
)
await monitor.start()

// Record each write operation
await monitor.recordWrite(duration: 0.010, bytesWritten: 4000)

// Check current state
let bitrate = await monitor.currentBitrate
let bandwidth = await monitor.estimatedBandwidth
let latency = await monitor.averageWriteLatency

// Listen for recommendations
for await recommendation in monitor.recommendations {
    print("Recommend \(recommendation.direction): \(recommendation.recommendedBitrate) bps")
}
```

The monitor detects three congestion signals:

1. **EWMA latency spike** — average write latency exceeds baseline × `downTriggerThreshold`
2. **RTT spike** — individual write latency exceeds 3× the EWMA average
3. **Bandwidth slowdown** — measured bandwidth drops below 85% of target bitrate

### Audio Quality Steps

``AudioQualityStep`` defines standard bitrate tiers per audio format:

| Format | Steps | Bitrate Range |
|--------|-------|---------------|
| MP3 | 7 tiers | 32–320 kbps |
| AAC | format-specific | format-specific |
| Opus | format-specific | format-specific |
| Vorbis | format-specific | format-specific |

```swift
let mp3Steps = AudioQualityStep.mp3Steps
let aacSteps = AudioQualityStep.aacSteps
let opusSteps = AudioQualityStep.opusSteps
let vorbisSteps = AudioQualityStep.vorbisSteps

// Get steps for any content type (falls back to MP3)
let steps = AudioQualityStep.steps(for: .oggOpus)

// Find closest step to a target bitrate
let closest = AudioQualityStep.closestStep(for: 96_000, contentType: .mp3)
```

### Bitrate Recommendation

``BitrateRecommendation`` carries the full context of a recommendation:

```swift
let rec = BitrateRecommendation(
    recommendedBitrate: 96_000,
    currentBitrate: 128_000,
    direction: .decrease,
    reason: .congestionDetected,
    confidence: 0.85
)
```

| Property | Type | Description |
|----------|------|-------------|
| `recommendedBitrate` | `Int` | Suggested bitrate (bps) |
| `currentBitrate` | `Int` | Current bitrate at time of recommendation |
| `direction` | `.increase` / `.decrease` / `.maintain` | Direction of change |
| `reason` | `.congestionDetected` / `.bandwidthRecovered` / `.rttSpike` / `.sendSlowdown` / `.stable` | Why |
| `confidence` | `Double` | 0.0–1.0 confidence level |

### Integration with IcecastClient

Enable ABR by passing a policy in ``IcecastConfiguration``:

```swift
let config = IcecastConfiguration(
    host: "radio.example.com",
    mountpoint: "/live.mp3",
    adaptiveBitrate: .conservative
)
```

Recommendations arrive as ``ConnectionEvent/bitrateRecommendation(_:)`` events:

```swift
for await event in client.events {
    if case .bitrateRecommendation(let rec) = event {
        print("\(rec.direction): \(rec.recommendedBitrate) bps (\(rec.reason))")
    }
}
```

## Next Steps

- <doc:ConnectionQualityGuide> — Quality scoring and health monitoring
- <doc:BandwidthProbingGuide> — Pre-stream bandwidth measurement
- <doc:MonitoringGuide> — Real-time events and statistics
