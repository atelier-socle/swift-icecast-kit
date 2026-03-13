# Advanced Authentication

Configure authentication beyond HTTP Basic: Digest, Bearer, Query Token, and URL-embedded credentials.

@Metadata {
    @PageKind(article)
}

## Overview

IcecastKit 0.3.0 adds ``IcecastAuthentication`` — a unified enum for all authentication methods. The existing ``IcecastCredentials``-based flow continues to work unchanged, while the new authentication system adds Digest (RFC 7616), Bearer token, query token, and SHOUTcast-specific variants.

### Authentication Types

``IcecastAuthentication`` supports six cases:

| Case | Description | Auth Header |
|------|-------------|-------------|
| `.basic(username:password:)` | HTTP Basic Auth (RFC 7617) | `Authorization: Basic <base64>` |
| `.digest(username:password:)` | HTTP Digest Auth (RFC 7616) | `Authorization: Digest ...` (after challenge) |
| `.bearer(token:)` | Bearer token | `Authorization: Bearer <token>` |
| `.queryToken(key:value:)` | Token in URL query string | Modifies mountpoint |
| `.shoutcast(password:)` | SHOUTcast v1 password-only | Password in handshake |
| `.shoutcastV2(password:streamId:)` | SHOUTcast v2 with stream ID | Password + stream ID |

### Basic Authentication

HTTP Basic Auth sends credentials as a Base64-encoded header:

```swift
let auth = IcecastAuthentication.basic(username: "source", password: "hackme")
let header = auth.initialAuthorizationHeader()
// "Basic c291cmNlOmhhY2ttZQ=="
```

### Bearer Token

Bearer tokens are sent as-is in the `Authorization` header:

```swift
let auth = IcecastAuthentication.bearer(token: "my-api-token-12345")
let header = auth.initialAuthorizationHeader()
// "Bearer my-api-token-12345"
```

Bearer authentication handles server responses:
- **401 Unauthorized** → throws ``IcecastError/tokenExpired``
- **403 Forbidden** → throws ``IcecastError/tokenInvalid``

Both are non-recoverable errors — reconnection is not attempted.

### Digest Authentication

Digest auth follows the RFC 7616 challenge-response flow. No credentials are sent on the first request. When the server responds with `401` and a `WWW-Authenticate: Digest` challenge, IcecastKit computes the digest response and retries:

```swift
let config = IcecastConfiguration(
    host: "radio.example.com",
    port: 8000,
    mountpoint: "/live.mp3",
    authentication: .digest(username: "source", password: "hackme")
)
```

The digest handler supports:
- **Algorithms**: MD5, SHA-256
- **Quality of Protection (qop)**: `auth`
- **Opaque**: forwarded from server challenge
- **cnonce/nc**: generated per request

```swift
let handler = DigestAuthHandler(username: "source", password: "hackme")
let challenge = handler.parseChallenge(
    "Digest realm=\"icecast\", nonce=\"abc123\", algorithm=MD5, qop=auth"
)
// challenge.realm == "icecast"
// challenge.algorithm == .md5
```

**Security**: Unlike Basic Auth, Digest Auth never sends the password over the wire. Instead, it sends a hash computed from the password, realm, nonce, and request URI.

If the server rejects the digest response (second 401), ``IcecastError/digestAuthFailed(reason:)`` is thrown.

### Query Token

Query tokens append a key-value pair to the mountpoint URL:

```swift
let auth = IcecastAuthentication.queryToken(key: "token", value: "abc123")
```

The token modifies the mountpoint in the HTTP request:

```swift
let qt = QueryTokenAuth(key: "token", value: "abc123")
let modified = qt.apply(to: "/live.mp3")
// "/live.mp3?token=abc123"

// Existing query parameters are preserved
let existing = qt.apply(to: "/live.mp3?format=mp3")
// "/live.mp3?format=mp3&token=abc123"
```

Special characters in the value are percent-encoded.

### URL-Embedded Credentials

Parse authentication from a URL with embedded credentials:

```swift
let auth = IcecastAuthentication.fromURL(
    "http://admin:secret@radio.example.com:8000/live.mp3"
)
// .basic(username: "admin", password: "secret")
```

Returns `nil` for URLs without credentials:

```swift
let none = IcecastAuthentication.fromURL("http://radio.example.com:8000/live.mp3")
// nil
```

Strip credentials from a URL for safe logging:

```swift
let clean = IcecastAuthentication.stripCredentials(
    from: "http://admin:secret@radio.example.com:8000/live.mp3"
)
// "http://radio.example.com:8000/live.mp3"
```

### Credentials Bridge

``IcecastAuthentication`` bridges to ``IcecastCredentials`` when applicable:

| Authentication | `.credentials` |
|---------------|----------------|
| `.basic` | `IcecastCredentials(username:password:)` |
| `.digest` | `IcecastCredentials(username:password:)` |
| `.shoutcast` | `IcecastCredentials(password:)` |
| `.shoutcastV2` | `IcecastCredentials(password:)` |
| `.bearer` | `nil` |
| `.queryToken` | `nil` |

The reverse bridge is also available:

```swift
let creds = IcecastCredentials(username: "source", password: "hackme")
let auth = creds.authentication
// .basic(username: "source", password: "hackme")
```

### Configuration

Set authentication on ``IcecastConfiguration``:

```swift
let config = IcecastConfiguration(
    host: "radio.example.com",
    port: 8000,
    mountpoint: "/live.mp3",
    authentication: .bearer(token: "my-api-token")
)
let client = IcecastClient(
    configuration: config,
    credentials: IcecastCredentials(password: "unused")
)
try await client.connect()
```

When both `authentication` and `credentials` are provided, `authentication` takes precedence.

### CLI Usage

The `icecast-cli stream` command supports authentication options:

```bash
# Digest authentication
icecast-cli stream audio.mp3 \
    --host radio.example.com \
    --auth-type digest \
    --username source \
    --password hackme

# Bearer token
icecast-cli stream audio.mp3 \
    --host radio.example.com \
    --auth-type bearer \
    --token my-api-token-12345
```

## Next Steps

- <doc:ServerPresetsGuide> — Pre-configured authentication for common servers
- <doc:StreamingGuide> — Connection lifecycle and streaming
- <doc:RelayGuide> — Relay with authenticated sources
