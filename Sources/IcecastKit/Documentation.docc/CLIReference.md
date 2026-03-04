# CLI Reference

Stream audio, test connections, and query server information from the command line.

@Metadata {
    @PageKind(article)
}

## Overview

`icecast-cli` is a command-line tool built on IcecastKit for streaming audio files, testing server connectivity, and querying server statistics. It supports all protocol variants (Icecast PUT, SOURCE, SHOUTcast v1/v2) and provides colored terminal output.

### Installation

Build from source:

```bash
swift build -c release
cp .build/release/icecast-cli /usr/local/bin/
```

### Commands Overview

| Command | Description |
|---------|-------------|
| `stream` | Stream an audio file to an Icecast/SHOUTcast server |
| `probe` | Measure upload bandwidth and latency |
| `relay` | Pull audio from an existing stream |
| `test-connection` | Test connectivity and authentication |
| `info` | Display server and mountpoint information |

### stream

Stream an audio file to an Icecast or SHOUTcast server.

```bash
icecast-cli stream <file> [options]
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `file` | Path to audio file (MP3, AAC, OGG) |

**Connection Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--host` | `localhost` | Server hostname |
| `--port` | `8000` | Server port |
| `--mountpoint` | `/stream` | Mountpoint path |
| `--username` | `source` | Auth username |
| `--password` | (required) | Auth password |

**Stream Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--content-type` | auto-detect | Audio type: `mp3`, `aac`, `ogg-vorbis`, `ogg-opus` |
| `--protocol` | `auto` | Protocol: `auto`, `icecast-put`, `icecast-source`, `shoutcast-v1`, `shoutcast-v2:<id>` |
| `--title` | none | Initial stream title |
| `--bitrate` | auto-detect | Bitrate in kbps for pacing |

**Flags:**

| Flag | Description |
|------|-------------|
| `--loop` | Loop the file continuously |
| `--no-reconnect` | Disable auto-reconnect |
| `--tls` | Use TLS/HTTPS |
| `--no-color` | Disable colored output |

**Multi-Destination Options:**

| Option | Description |
|--------|-------------|
| `--dest` | Add destination as `label:host:port:mountpoint:password` (repeatable) |

**Authentication Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--auth-type` | `basic` | Authentication type: `basic`, `digest`, `bearer`, `query-token` |
| `--token` | none | Bearer token (when `--auth-type bearer`) |

### probe

Measure upload bandwidth and latency to a streaming server.

```bash
icecast-cli probe [options]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--host` | `localhost` | Server hostname |
| `--port` | `8000` | Server port |
| `--mountpoint` | `/probe` | Mountpoint for probe |
| `--username` | `source` | Auth username |
| `--password` | (required) | Auth password |
| `--duration` | `5` | Probe duration in seconds (2–30) |
| `--content-type` | `mp3` | Audio type: `mp3`, `aac`, `ogg-vorbis`, `ogg-opus` |
| `--no-color` | `false` | Disable colored output |

### relay

Pull audio from an existing stream and optionally re-publish or record.

```bash
icecast-cli relay [options]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--source` | (required) | Source stream URL |
| `--dest` | none | Re-publish destination `label:host:port:mountpoint:password` (repeatable) |
| `--record` | none | Recording output directory |
| `--duration` | unlimited | Maximum relay duration in seconds |
| `--no-color` | `false` | Disable colored output |

### test-connection

Test connectivity and authentication to a streaming server. Connects, negotiates the protocol, then immediately disconnects.

```bash
icecast-cli test-connection [options]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--host` | `localhost` | Server hostname |
| `--port` | `8000` | Server port |
| `--mountpoint` | `/stream` | Mountpoint path |
| `--username` | `source` | Auth username |
| `--password` | none | Auth password (required for basic/digest) |
| `--protocol` | `auto` | Protocol variant |
| `--auth-type` | `basic` | Authentication type: `basic`, `digest`, `bearer`, `query-token` |
| `--token` | none | Token for `--auth-type bearer` or `query-token` |
| `--tls` | `false` | Use TLS/HTTPS |
| `--no-color` | `false` | Disable colored output |

### info

Display server and mountpoint information via the Icecast admin API.

```bash
icecast-cli info [options]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--host` | `localhost` | Server hostname |
| `--port` | `8000` | Server port |
| `--admin-user` | `admin` | Admin username |
| `--admin-pass` | (required) | Admin password |
| `--mountpoint` | none | Specific mountpoint to query |
| `--tls` | `false` | Use TLS/HTTPS |
| `--no-color` | `false` | Disable colored output |

Without `--mountpoint`, displays global server statistics. With `--mountpoint`, displays stats for that specific mount.

### Exit Codes

| Code | Name | Description |
|------|------|-------------|
| `0` | Success | Successful execution |
| `1` | General Error | Unclassified error |
| `2` | Connection Error | TCP connection failed, lost, or timed out |
| `3` | Auth Error | Authentication rejected or credentials missing |
| `4` | File Error | Audio file not found or unreadable |
| `5` | Argument Error | Invalid command-line arguments |
| `6` | Server Error | Server-side error (mountpoint in use, content type rejected) |
| `7` | Timeout | Connection or operation timed out |

### Examples

Stream an MP3 file with metadata:

```bash
icecast-cli stream music.mp3 --host radio.example.com --password hackme --title "My Show"
```

Test connection to an Icecast server:

```bash
icecast-cli test-connection --host radio.example.com --password hackme
```

Query server information:

```bash
icecast-cli info --host radio.example.com --admin-pass hackme
```

Stream with SHOUTcast v1 protocol and looping:

```bash
icecast-cli stream music.mp3 --password hackme --loop --protocol shoutcast-v1
```

Stream with SHOUTcast v2 multi-stream:

```bash
icecast-cli stream music.mp3 --password hackme --protocol shoutcast-v2:3
```

Stream to multiple destinations:

```bash
icecast-cli stream music.mp3 \
    --dest "primary:radio1.example.com:8000:/live.mp3:secret1" \
    --dest "backup:backup.example.com:8000:/live.mp3:secret2"
```

Stream with digest authentication:

```bash
icecast-cli stream music.mp3 --host radio.example.com --password hackme --auth-type digest
```

Stream with bearer token:

```bash
icecast-cli stream music.mp3 --host radio.example.com --auth-type bearer --token my-api-token
```

Probe bandwidth before streaming:

```bash
icecast-cli probe --host radio.example.com --port 8000 --password hackme --duration 10
```

Relay and record a stream:

```bash
icecast-cli relay --source http://radio.example.com:8000/live.mp3 --record /recordings/ --duration 3600
```

## Next Steps

- <doc:TestingGuide> — Mock server for testing CLI commands
- <doc:GettingStarted> — Using IcecastKit as a library
- <doc:StreamingGuide> — Programmatic streaming configuration
