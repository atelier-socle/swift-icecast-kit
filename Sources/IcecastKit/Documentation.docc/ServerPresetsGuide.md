# Server Presets

Pre-configured settings for popular Icecast and SHOUTcast hosting platforms.

@Metadata {
    @PageKind(article)
}

## Overview

``IcecastServerPreset`` provides one-line configuration for 7 popular streaming server platforms. Each preset knows the default port, mountpoint, authentication style, and protocol mode for its platform.

### Available Presets

| Preset | Default Port | Mountpoint | Auth Style | Protocol |
|--------|-------------|------------|------------|----------|
| `.azuracast` | 8000 | `/radio.mp3` | Basic Auth | Icecast PUT |
| `.libretime` | 8000 | `/main.mp3` | Basic Auth | Icecast PUT |
| `.radioCo` | 8000 | `/radio.mp3` | Bearer Token | Icecast PUT |
| `.centovaCast` | 8000 | `/stream` | SHOUTcast v2 | SHOUTcast v2 |
| `.shoutcastDNAS` | 8000 | `/stream` | Password Only | SHOUTcast v1 |
| `.icecastOfficial` | 8000 | `/stream.mp3` | Basic Auth | Icecast PUT |
| `.broadcastify` | 80 | `/stream` | Bearer Token | Icecast PUT |

### Creating a Configuration

Use ``IcecastServerPreset/configuration(host:port:mountpoint:password:contentType:)`` to generate a complete ``IcecastConfiguration``:

```swift
let config = IcecastServerPreset.azuracast.configuration(
    host: "mystation.azuracast.com",
    password: "my-source-password"
)
// config.credentials?.username == "source"
// config.mountpoint == "/radio.mp3"
// config.protocolMode == .icecastPUT
```

Override any default:

```swift
let config = IcecastServerPreset.icecastOfficial.configuration(
    host: "radio.example.com",
    port: 9000,
    mountpoint: "/custom.mp3",
    password: "hackme",
    contentType: .aac
)
// config.port == 9000
// config.mountpoint == "/custom.mp3"
// config.contentType == .aac
```

### Authentication Styles

Each preset uses one of four ``PresetAuthStyle`` values:

| Style | Behavior |
|-------|----------|
| `.basicAuth` | HTTP Basic with `source` username |
| `.passwordOnly` | SHOUTcast v1 password-only authentication |
| `.shoutcastV2` | SHOUTcast v2 with stream ID |
| `.bearerToken` | Bearer token in `Authorization` header |

```swift
let preset = IcecastServerPreset.radioCo
// preset.authenticationStyle == .bearerToken

let config = preset.configuration(
    host: "streaming.radio.co",
    password: "api-token-xyz"
)
if case .bearer(let token) = config.authentication {
    // token == "api-token-xyz"
}
```

### Applying to Existing Configuration

``IcecastServerPreset/apply(to:)`` patches an existing configuration with preset defaults:

```swift
var config = IcecastConfiguration(
    host: "radio.example.com",
    mountpoint: "/live.mp3",
    credentials: IcecastCredentials(password: "secret")
)

IcecastServerPreset.broadcastify.apply(to: &config)
// config.port == 80
// config.protocolMode == .icecastPUT
// config.authentication == .bearer(...)
```

### Preset Metadata

Each preset provides display metadata:

```swift
for preset in IcecastServerPreset.allCases {
    print("\(preset.displayName): \(preset.presetDescription)")
}
```

| Property | Description |
|----------|-------------|
| `displayName` | Human-readable name |
| `presetDescription` | One-line description |
| `defaultPort` | Default server port |
| `defaultMountpoint` | Default mountpoint path |
| `authenticationStyle` | Authentication method |
| `protocolMode` | Protocol variant |

### All Presets

``IcecastServerPreset`` conforms to `CaseIterable` with 7 cases:

```swift
let presets = IcecastServerPreset.allCases
// presets.count == 7

for preset in presets {
    let config = preset.configuration(
        host: "test.example.com",
        password: "testpass"
    )
    print("\(preset.displayName): \(config.host):\(config.port)\(config.mountpoint)")
}
```

## Next Steps

- <doc:AuthenticationGuide> — Authentication details for each method
- <doc:StreamingGuide> — Connection lifecycle and streaming
- <doc:GettingStarted> — Quick start guide
