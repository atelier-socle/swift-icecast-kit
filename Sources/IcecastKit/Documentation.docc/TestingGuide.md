# Testing Guide

Use the mock server for manual testing and run the unit test suite.

@Metadata {
    @PageKind(article)
}

## Overview

IcecastKit includes a Python mock server for manual CLI testing and a comprehensive unit test suite. This guide covers setting up the mock server, running test scenarios, and measuring code coverage.

### Mock Icecast Server

The mock server at `Scripts/mock-icecast-server.py` simulates Icecast and SHOUTcast server behavior for local testing.

### Starting the Server

```bash
python3 Scripts/mock-icecast-server.py
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--port` | `8000` | Listen port |
| `--mode` | `icecast-put` | Server mode |
| `--fail` | none | Error simulation mode |

### Server Modes

| Mode | Description |
|------|-------------|
| `icecast-put` | Icecast HTTP PUT protocol (default) |
| `icecast-source` | Icecast legacy SOURCE protocol |
| `shoutcast` | SHOUTcast v1/v2 password authentication |

```bash
# Start in Icecast PUT mode (default)
python3 Scripts/mock-icecast-server.py --port 8000 --mode icecast-put

# Start in SHOUTcast mode
python3 Scripts/mock-icecast-server.py --port 8000 --mode shoutcast

# Start in legacy SOURCE mode
python3 Scripts/mock-icecast-server.py --port 8000 --mode icecast-source
```

### Error Simulation

Simulate server errors to test error handling:

| Fail Mode | Response |
|-----------|----------|
| `401` | 401 Unauthorized (authentication failure) |
| `403-mount-in-use` | 403 Mountpoint in use |
| `500` | 500 Internal Server Error |

```bash
# Simulate auth failure
python3 Scripts/mock-icecast-server.py --fail 401

# Simulate mountpoint conflict
python3 Scripts/mock-icecast-server.py --fail 403-mount-in-use

# Simulate server error
python3 Scripts/mock-icecast-server.py --fail 500
```

### Testing Scenarios

**Test connection:**

```bash
# Terminal 1: start mock server
python3 Scripts/mock-icecast-server.py

# Terminal 2: test connection
icecast-cli test-connection --password hackme
```

**Stream a file:**

```bash
# Terminal 1: start mock server
python3 Scripts/mock-icecast-server.py

# Terminal 2: stream audio
icecast-cli stream test.mp3 --password hackme --title "Test"
```

**Stream with looping:**

```bash
icecast-cli stream test.mp3 --password hackme --loop
```

**Query server info:**

```bash
# Terminal 1: start mock server
python3 Scripts/mock-icecast-server.py

# Terminal 2: query info (mock supports admin API)
icecast-cli info --admin-pass hackme
```

**Test authentication failure:**

```bash
# Terminal 1: start mock server with auth failure
python3 Scripts/mock-icecast-server.py --fail 401

# Terminal 2: test connection (should fail with exit code 3)
icecast-cli test-connection --password hackme
```

### Creating Test Audio Files

Generate a minimal MP3-like test file with Python:

```bash
python3 -c "import os; open('test.mp3','wb').write(os.urandom(1048576))"
```

This creates a 1 MB file of random bytes, sufficient for testing the streaming pipeline (the mock server accepts any data).

### Unit Tests

Run the full test suite:

```bash
swift test
```

The test suite uses Swift Testing (not XCTest) covering the complete API surface.

### Code Coverage

Generate a coverage report:

```bash
swift test --enable-code-coverage

# View the coverage report
xcrun llvm-cov report \
    .build/debug/swift-icecast-kitPackageTests.xctest/Contents/MacOS/swift-icecast-kitPackageTests \
    -instr-profile .build/debug/codecov/default.profdata \
    -ignore-filename-regex "Tests/"
```

The current coverage target is 97%+ for IcecastKit sources (excluding platform-specific transport implementations).

## Next Steps

- <doc:CLIReference> — Full CLI command reference
- <doc:GettingStarted> — Getting started with the library API
- <doc:StreamingGuide> — Programmatic streaming workflows
