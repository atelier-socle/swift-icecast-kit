# Reconnection Guide

Configure automatic reconnection with exponential backoff and jitter.

@Metadata {
    @PageKind(article)
}

## Overview

IcecastKit provides built-in automatic reconnection when a connection is lost during streaming. The ``ReconnectPolicy`` struct controls retry behavior with exponential backoff and configurable jitter to prevent thundering herd problems.

### ReconnectPolicy

``ReconnectPolicy`` has six configurable properties:

| Property | Type | Description |
|----------|------|-------------|
| `isEnabled` | `Bool` | Whether auto-reconnect is active |
| `maxRetries` | `Int` | Maximum retry attempts before giving up |
| `initialDelay` | `TimeInterval` | Delay before the first retry |
| `maxDelay` | `TimeInterval` | Maximum delay cap (prevents unbounded growth) |
| `backoffMultiplier` | `Double` | Multiplier applied to delay each attempt |
| `jitterFactor` | `Double` | Random jitter factor (0.0-1.0) |

### Presets

IcecastKit includes four preset policies:

| Preset | Retries | Initial Delay | Max Delay | Multiplier | Jitter |
|--------|---------|---------------|-----------|------------|--------|
| `.default` | 10 | 1.0s | 60.0s | 2.0x | 0.25 |
| `.none` | 0 | — | — | — | — |
| `.aggressive` | 20 | 0.5s | 30.0s | 1.5x | 0.1 |
| `.conservative` | 5 | 5.0s | 120.0s | 3.0x | 0.25 |

```swift
// Use the default policy (enabled by default)
let client = IcecastClient(
    configuration: configuration,
    credentials: credentials
)

// Disable reconnection
let client2 = IcecastClient(
    configuration: configuration,
    credentials: credentials,
    reconnectPolicy: .none
)

// Use aggressive reconnection for low-latency scenarios
let client3 = IcecastClient(
    configuration: configuration,
    credentials: credentials,
    reconnectPolicy: .aggressive
)
```

### Delay Calculation

The delay for each attempt follows this formula:

```
delay = min(initialDelay x backoffMultiplier^attempt, maxDelay) +/- (jitterFactor x random)
```

For the default policy (1.0s initial, 2.0x multiplier, 60s max, 0.25 jitter):

| Attempt | Base Delay | With Jitter (range) |
|---------|------------|---------------------|
| 0 | 1.0s | 0.75s - 1.25s |
| 1 | 2.0s | 1.50s - 2.50s |
| 2 | 4.0s | 3.00s - 5.00s |
| 3 | 8.0s | 6.00s - 10.00s |
| 4 | 16.0s | 12.00s - 20.00s |
| 5 | 32.0s | 24.00s - 40.00s |
| 6+ | 60.0s (capped) | 45.00s - 75.00s |

### Custom Policies

Create a custom policy for specific requirements:

```swift
let customPolicy = ReconnectPolicy(
    isEnabled: true,
    maxRetries: 50,
    initialDelay: 0.1,
    maxDelay: 10.0,
    backoffMultiplier: 1.5,
    jitterFactor: 0.1
)

let client = IcecastClient(
    configuration: configuration,
    credentials: credentials,
    reconnectPolicy: customPolicy
)
```

You can also update the policy at runtime:

```swift
await client.updateReconnectPolicy(.conservative)
```

### State Transitions During Reconnection

When a connection is lost during streaming, the client enters the reconnection loop:

1. **Connection lost** — `send()` throws an error
2. **State: `.reconnecting(attempt: 0, nextRetryIn: delay)`** — emits ``ConnectionEvent/reconnecting(attempt:delay:)``
3. **Wait** — delays for the calculated interval
4. **Retry** — attempts to reconnect and re-negotiate the protocol
5. **Success** — state transitions to `.connected`, emits ``ConnectionEvent/connected(host:port:mountpoint:protocolName:)``
6. **Failure** — increments attempt count, loops back to step 2
7. **Max retries exceeded** — state transitions to `.failed`, emits ``ConnectionEvent/disconnected(reason:)`` with `.maxRetriesExceeded``

### Non-Recoverable Errors

Certain errors are considered non-recoverable and skip the reconnection loop entirely, transitioning directly to `.failed`:

| Error | Reason |
|-------|--------|
| ``IcecastError/authenticationFailed(statusCode:message:)`` | Server rejected credentials |
| ``IcecastError/mountpointInUse(_:)`` | Another source is using the mountpoint |
| ``IcecastError/contentTypeNotSupported(_:)`` | Server does not support the content type |
| ``IcecastError/credentialsRequired`` | No credentials provided |

### Cancellation

Calling ``IcecastClient/disconnect()`` during reconnection cancels the loop immediately:

```swift
// Connection lost, client is reconnecting...
await client.disconnect()
// state == .disconnected (reconnection cancelled)
```

## Next Steps

- <doc:MonitoringGuide> — Track reconnection events and statistics
- <doc:StreamingGuide> — Connection lifecycle and state machine
- <doc:GettingStarted> — Basic setup and quick start
