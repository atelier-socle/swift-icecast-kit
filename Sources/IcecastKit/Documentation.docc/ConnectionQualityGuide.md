# Connection Quality

Monitor connection health with a composite quality score and actionable recommendations.

@Metadata {
    @PageKind(article)
}

## Overview

IcecastKit computes a real-time connection quality score from multiple metrics. The score ranges from 0.0 (critical) to 1.0 (excellent) and drives automatic recommendations for improving stream stability.

### Quality Score

``ConnectionQuality`` is computed from five weighted metrics:

| Metric | Weight | Description |
|--------|--------|-------------|
| Write Latency | 30% | Average write latency (lower is better) |
| Throughput | 25% | Current bitrate vs. target bitrate ratio |
| Stability | 20% | Latency variance (lower variance is better) |
| Send Success | 15% | Ratio of successful sends to total sends |
| Reconnection | 10% | Reconnection frequency (fewer is better) |

```swift
let stats = ConnectionStatistics(
    bytesSent: 1_000_000,
    bytesTotal: 1_000_000,
    duration: 60.0,
    averageBitrate: 128_000,
    currentBitrate: 128_000,
    averageWriteLatency: 5.0,
    writeLatencyVariance: 0.5,
    totalSendCount: 100
)
let quality = ConnectionQuality.from(statistics: stats)
print("Score: \(quality.score)")   // 0.95+
print("Grade: \(quality.grade)")   // .excellent
```

You can also provide an explicit target bitrate for throughput scoring:

```swift
let quality = ConnectionQuality.from(
    statistics: stats, targetBitrate: 128_000
)
```

### Quality Grades

``QualityGrade`` maps the composite score to a human-readable grade:

| Grade | Score Range | Label |
|-------|------------|-------|
| `.excellent` | 0.91–1.00 | Excellent |
| `.good` | 0.71–0.90 | Good |
| `.fair` | 0.51–0.70 | Fair |
| `.poor` | 0.31–0.50 | Poor |
| `.critical` | 0.00–0.30 | Critical |

``QualityGrade`` conforms to `Comparable`:

```swift
#expect(QualityGrade.excellent > .good)
#expect(QualityGrade.good > .fair)
#expect(QualityGrade.fair > .poor)
#expect(QualityGrade.poor > .critical)
```

### Individual Scores

``ConnectionQuality`` exposes each component score for detailed diagnostics:

```swift
let quality = ConnectionQuality.from(statistics: stats)
print("Write latency: \(quality.writeLatencyScore)")
print("Stability:     \(quality.stabilityScore)")
print("Throughput:    \(quality.throughputScore)")
print("Send success:  \(quality.sendSuccessScore)")
print("Reconnection:  \(quality.reconnectionScore)")
```

### Recommendation Engine

``QualityRecommendationEngine`` generates actionable recommendations based on the quality score:

```swift
let engine = QualityRecommendationEngine()

let quality = ConnectionQuality.from(statistics: stats)
if let recommendation = engine.recommendation(for: quality) {
    print("Recommendation: \(recommendation)")
}
// Returns nil for .excellent grade (no action needed)
```

### Integration with IcecastClient

Quality changes arrive as ``ConnectionEvent`` cases:

| Event | Description |
|-------|-------------|
| `.qualityChanged(_:)` | Quality score updated with new ``ConnectionQuality`` |
| `.qualityWarning(_:)` | Quality dropped below threshold — includes recommendation text |

```swift
for await event in client.events {
    switch event {
    case .qualityChanged(let quality):
        print("\(quality.grade.label): \(quality.score)")
    case .qualityWarning(let message):
        print("Warning: \(message)")
    default:
        break
    }
}
```

Access the current quality directly:

```swift
let quality = await client.connectionQuality
if let q = quality {
    print("Score: \(q.score), Grade: \(q.grade.label)")
}
```

### Edge Cases

The quality computation handles edge cases gracefully:

- **Zero-duration statistics** — returns default scores (throughput and send success = 1.0)
- **No sends yet** — send success score is 1.0
- **No reconnections** — reconnection score is 1.0

## Next Steps

- <doc:AdaptiveBitrateGuide> — Automatic bitrate adjustment based on quality
- <doc:BandwidthProbingGuide> — Pre-stream bandwidth measurement
- <doc:MonitoringGuide> — Real-time events and statistics
