# Stream Recording

Record streamed audio to disk with automatic file rotation.

@Metadata {
    @PageKind(article)
}

## Overview

``StreamRecorder`` is a standalone actor that writes audio data to files on disk. It supports automatic file rotation by size or time interval, configurable filename patterns, and format-aware file extensions. The recorder works both standalone and integrated with ``IcecastClient``.

### Standalone Recording

``StreamRecorder`` can record any audio data independently of ``IcecastClient``:

```swift
let config = RecordingConfiguration(
    directory: "/path/to/recordings",
    contentType: .mp3,
    flushInterval: 0
)
let recorder = StreamRecorder(configuration: config)

try await recorder.start()
// recorder.isRecording == true

let audioData = Data(repeating: 0xCD, count: 2048)
try await recorder.write(audioData)

let stats = await recorder.statistics
print("Bytes written: \(stats.bytesWritten)")

let finalStats = try await recorder.stop()
print("Files created: \(finalStats.filesCreated)")
```

### Recording Configuration

``RecordingConfiguration`` controls all recording parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `directory` | `String` | (required) | Output directory path |
| `contentType` | ``AudioContentType`` | (required) | Audio format for file extension |
| `format` | ``RecordingFormat`` | `.matchSource` | `.matchSource` or `.raw` |
| `maxFileSize` | `Int64?` | `nil` | Rotate when file exceeds this size |
| `splitInterval` | `TimeInterval?` | `nil` | Rotate at this time interval |
| `flushInterval` | `TimeInterval` | `1.0` | Flush-to-disk interval |
| `filenamePattern` | `String` | `"{date}_{mountpoint}"` | Filename template |

### File Rotation

``FileRotationPolicy`` controls when the recorder creates a new file:

```swift
// Rotate when file exceeds 50 MB
let policy = FileRotationPolicy.maxSize(50_000_000)

// Rotate every hour
let hourly = FileRotationPolicy.hourly

// Rotate every 30 minutes
let half = FileRotationPolicy.every(1800)

// No rotation
let none = FileRotationPolicy.none
```

You can also set rotation via ``RecordingConfiguration``:

```swift
let config = RecordingConfiguration(
    directory: "/recordings",
    contentType: .mp3,
    maxFileSize: 500,
    flushInterval: 0
)
let recorder = StreamRecorder(configuration: config)
try await recorder.start()

// Writing more than maxFileSize triggers rotation
let data = Data(repeating: 0xFF, count: 600)
try await recorder.write(data)

let stats = try await recorder.stop()
// stats.filesCreated == 2
```

### Filename Tokens

The `filenamePattern` property supports three tokens:

| Token | Description | Example |
|-------|-------------|---------|
| `{date}` | ISO 8601 date/time | `2026-03-04T14-30-00` |
| `{mountpoint}` | Sanitized mountpoint | `live_mp3` |
| `{index}` | File index (1-based) | `1`, `2`, `3` |

```swift
let config = RecordingConfiguration(
    directory: "/recordings",
    contentType: .mp3,
    flushInterval: 0,
    filenamePattern: "{mountpoint}_{index}"
)
let recorder = StreamRecorder(configuration: config)
try await recorder.start(mountpoint: "/live.mp3")
// Creates: live_mp3_1.mp3
```

Mountpoints are sanitized — slashes and dots are replaced with underscores.

### Recording Format

``RecordingFormat`` controls the file extension:

| Format | Behavior |
|--------|----------|
| `.matchSource` | Uses the content type extension (`.mp3`, `.aac`, `.ogg`, `.opus`) |
| `.raw` | Always uses `.raw` extension |

### Recording Statistics

``RecordingStatistics`` provides a snapshot of the recording session:

```swift
let stats = RecordingStatistics(
    duration: 60.0,
    bytesWritten: 1_000_000,
    filesCreated: 3,
    currentFilePath: "/tmp/test.mp3",
    isRecording: true
)
```

### Integration with IcecastClient

Enable auto-recording by setting ``IcecastConfiguration/recording``:

```swift
let config = IcecastConfiguration(
    host: "radio.example.com",
    mountpoint: "/live.mp3",
    recording: RecordingConfiguration(
        directory: "/recordings",
        contentType: .mp3,
        maxFileSize: 500,
        flushInterval: 0
    )
)
```

Recording events arrive through the event stream:

| Event | Description |
|-------|-------------|
| `.recordingStarted(path:)` | Recording started, file path provided |
| `.recordingStopped(statistics:)` | Recording stopped with final stats |
| `.recordingFileRotated(newPath:)` | File rotation occurred |
| `.recordingError(_:)` | Recording error |

## Next Steps

- <doc:RelayGuide> — Relay incoming streams and record them
- <doc:StreamingGuide> — Connection lifecycle and streaming
- <doc:MonitoringGuide> — Real-time events and statistics
