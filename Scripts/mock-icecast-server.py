#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Atelier Socle SAS

"""Mock Icecast/SHOUTcast server for manual CLI testing.

Supports Icecast PUT/SOURCE handshakes, SHOUTcast v1 password auth,
admin API endpoints, relay/listener audio serving, Digest auth
challenges, Bearer token validation, bandwidth probe mode, and
dual-port operation for multi-destination testing.

Usage examples:
    # Basic PUT mode
    python3 mock-icecast-server.py --port 8000

    # Relay mode — serve audio with ICY metadata
    python3 mock-icecast-server.py --port 8000 --serve-relay

    # Digest auth challenge
    python3 mock-icecast-server.py --port 8000 --fail digest-challenge

    # Bearer token validation
    python3 mock-icecast-server.py --port 8000 --bearer-token "my-token"

    # Bandwidth probe mode
    python3 mock-icecast-server.py --port 8000 --probe-mode

    # Dual-port for multi-destination
    python3 mock-icecast-server.py --port 8000 --port2 8001
"""

import hashlib
import socket
import struct
import threading
import time
import sys
import os

# ANSI colors
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
DIM = "\033[2m"
RESET = "\033[0m"


class MockIcecastServer:
    """A mock Icecast/SHOUTcast server for testing IcecastKit.

    Handles PUT, SOURCE, and SHOUTcast handshakes, admin API endpoints,
    and various authentication/failure modes.
    """

    def __init__(self, port=8000, mode="icecast-put", fail_mode=None,
                 serve_relay=False, relay_metaint=8192,
                 relay_metadata="Mock Artist - Mock Song",
                 relay_title="Mock Radio",
                 bearer_token=None, probe_mode=False, probe_duration=3.0,
                 label=None):
        self.port = port
        self.mode = mode
        self.fail_mode = fail_mode
        self.serve_relay = serve_relay
        self.relay_metaint = relay_metaint
        self.relay_metadata = relay_metadata
        self.relay_title = relay_title
        self.bearer_token = bearer_token
        self.probe_mode = probe_mode
        self.probe_duration = probe_duration
        self.label = label or f"port {port}"
        self.server = None
        self.running = False
        # Counters
        self.total_bytes_received = 0
        self.total_bytes_sent = 0
        self.connections = 0
        self.metadata_updates = 0
        self.digest_challenges_sent = 0
        self.digest_auth_succeeded = 0
        self.bearer_accepted = 0
        self.bearer_rejected = 0
        # Digest auth: track connections that already received a challenge
        self._digest_challenged = set()

    def start(self):
        """Start listening for connections. Blocks until stopped."""
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(("0.0.0.0", self.port))
        self.server.listen(5)
        self.server.settimeout(1.0)
        self.running = True
        print(f"{GREEN}▶ Mock server started on port {self.port} (mode: {self.mode}){RESET}")
        if self.fail_mode:
            print(f"{YELLOW}  Fail mode: {self.fail_mode}{RESET}")
        if self.serve_relay:
            print(f"{CYAN}  Relay mode: serving audio with ICY metadata{RESET}")
            print(f"{DIM}  icy-metaint: {self.relay_metaint}, "
                  f"title: \"{self.relay_title}\", "
                  f"metadata: \"{self.relay_metadata}\"{RESET}")
        if self.bearer_token:
            print(f"{CYAN}  Bearer token required: {self.bearer_token}{RESET}")
        if self.probe_mode:
            print(f"{CYAN}  Probe mode: disconnect after {self.probe_duration}s{RESET}")
        print(f"{DIM}  Ctrl+C to stop{RESET}\n")

        while self.running:
            try:
                client, addr = self.server.accept()
                self.connections += 1
                print(f"{CYAN}← [{self.label}] Connection #{self.connections} "
                      f"from {addr[0]}:{addr[1]}{RESET}")
                t = threading.Thread(target=self.handle_client, args=(client, addr))
                t.daemon = True
                t.start()
            except socket.timeout:
                continue
            except OSError:
                break

    def handle_client(self, client, addr):
        """Route an incoming connection to the appropriate handler."""
        try:
            # Read first line to distinguish HTTP from SHOUTcast v1.
            # SHOUTcast v1 sends only "password\r\n" (no \r\n\r\n),
            # while HTTP methods (PUT, SOURCE, GET) send full headers
            # terminated by \r\n\r\n.
            first_data = b""
            while b"\r\n" not in first_data:
                chunk = client.recv(4096)
                if not chunk:
                    return
                first_data += chunk

            first_line = first_data.split(b"\r\n")[0].decode(
                "utf-8", errors="replace"
            )
            http_methods = ("PUT ", "SOURCE ", "GET ", "POST ", "HEAD ")
            is_http = any(first_line.startswith(m) for m in http_methods)

            if is_http:
                # HTTP request — continue reading until \r\n\r\n
                data = first_data
                while b"\r\n\r\n" not in data:
                    chunk = client.recv(4096)
                    if not chunk:
                        return
                    data += chunk
                self._handle_http_request(client, data)
            else:
                # SHOUTcast v1 — first line is the password
                self._handle_shoutcast_v1(client, first_line)

        except Exception as e:
            print(f"{RED}  Error: {e}{RESET}")
        finally:
            try:
                client.close()
            except Exception:
                pass

    def _handle_http_request(self, client, data):
        """Handle an HTTP-based request (Icecast PUT/SOURCE, admin, relay)."""
        request = data.split(b"\r\n\r\n")[0].decode("utf-8", errors="replace")
        lines = request.split("\r\n")
        method_line = lines[0] if lines else ""
        headers = {}
        for line in lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()

        print(f"{DIM}  Request: {method_line}{RESET}")
        for k, v in headers.items():
            if k in ("authorization", "content-type", "ice-name", "user-agent"):
                print(f"{DIM}  {k}: {v}{RESET}")

        # --- Admin API ---
        if method_line.startswith("GET /admin/"):
            self.handle_admin(client, method_line, headers)
            return

        # --- Relay / Listener GET ---
        if self.serve_relay and method_line.startswith("GET "):
            self.handle_relay_get(client, method_line, headers)
            return

        # --- Bearer token validation ---
        if self.bearer_token:
            auth_header = headers.get("authorization", "")
            if not auth_header.startswith("Bearer "):
                client.sendall(b"HTTP/1.1 401 Unauthorized\r\n\r\n")
                self.bearer_rejected += 1
                print(f"{RED}  → 401 Unauthorized (no Bearer token){RESET}")
                client.close()
                return
            received_token = auth_header[len("Bearer "):]
            if received_token != self.bearer_token:
                client.sendall(b"HTTP/1.1 403 Forbidden\r\n\r\n")
                self.bearer_rejected += 1
                print(f"{RED}  → 403 Forbidden (wrong token: "
                      f"\"{received_token}\"){RESET}")
                client.close()
                return
            self.bearer_accepted += 1
            print(f"{GREEN}  ✓ Bearer token accepted{RESET}")

        # --- Fail modes ---
        if self.fail_mode == "401":
            client.sendall(b"HTTP/1.1 401 Unauthorized\r\n\r\n")
            print(f"{RED}  → 401 Unauthorized{RESET}")
            client.close()
            return
        if self.fail_mode == "403-mount-in-use":
            client.sendall(b"HTTP/1.1 403 Mountpoint in use\r\n\r\n")
            print(f"{RED}  → 403 Mountpoint in use{RESET}")
            client.close()
            return
        if self.fail_mode == "500":
            client.sendall(b"HTTP/1.1 500 Internal Server Error\r\n\r\n")
            print(f"{RED}  → 500 Internal Server Error{RESET}")
            client.close()
            return
        if self.fail_mode == "digest-challenge":
            if self._handle_digest_challenge(client, headers, reject_always=False):
                return
        if self.fail_mode == "digest-always-reject":
            if self._handle_digest_challenge(client, headers, reject_always=True):
                return

        # --- Icecast PUT ---
        if method_line.startswith("PUT "):
            client.sendall(b"HTTP/1.1 200 OK\r\n\r\n")
            print(f"{GREEN}  → 200 OK (Icecast PUT){RESET}")
            self.receive_audio(client)

        # --- Icecast SOURCE ---
        elif method_line.startswith("SOURCE "):
            client.sendall(b"HTTP/1.0 200 OK\r\n\r\n")
            print(f"{GREEN}  → 200 OK (Icecast SOURCE){RESET}")
            self.receive_audio(client)

        else:
            print(f"{RED}  Unknown HTTP method: {method_line}{RESET}")

    def _handle_shoutcast_v1(self, client, password_line):
        """Handle a SHOUTcast v1 connection (password → OK2 → headers → audio)."""
        password_line = password_line.strip()
        print(f"{DIM}  SHOUTcast password received: {password_line}{RESET}")
        client.sendall(b"OK2\r\nicy-caps:11\r\n\r\n")
        print(f"{GREEN}  → OK2 (SHOUTcast){RESET}")
        # Read headers after auth (terminated by \r\n\r\n)
        header_data = b""
        while b"\r\n\r\n" not in header_data:
            chunk = client.recv(4096)
            if not chunk:
                return
            header_data += chunk
        sc_headers = header_data.decode("utf-8", errors="replace")
        print(f"{DIM}  SHOUTcast headers received ({len(sc_headers)} bytes){RESET}")
        self.receive_audio(client)

    def receive_audio(self, client):
        """Receive and count audio data bytes."""
        print(f"{GREEN}  ▶ Receiving audio stream...{RESET}")
        session_bytes = 0
        start = time.time()
        try:
            while self.running:
                # Probe mode: disconnect after probe_duration
                if self.probe_mode:
                    elapsed = time.time() - start
                    if elapsed >= self.probe_duration:
                        rate_bps = session_bytes / max(elapsed, 0.001)
                        print(f"\n{YELLOW}  ■ Probe ended after {elapsed:.1f}s: "
                              f"{session_bytes:,} bytes "
                              f"({rate_bps:,.0f} bytes/s){RESET}")
                        return

                data = client.recv(8192)
                if not data:
                    break
                session_bytes += len(data)
                self.total_bytes_received += len(data)
                elapsed = time.time() - start
                rate = (session_bytes * 8 / 1000 / max(elapsed, 0.001))
                sys.stdout.write(
                    f"\r{DIM}  Audio: {session_bytes:,} bytes "
                    f"({elapsed:.1f}s, {rate:.0f} kbps){RESET}  "
                )
                sys.stdout.flush()
        except (ConnectionResetError, BrokenPipeError):
            pass
        print(f"\n{YELLOW}  ■ Stream ended: {session_bytes:,} bytes received{RESET}")

    # ------------------------------------------------------------------ #
    # Relay / Listener mode                                                #
    # ------------------------------------------------------------------ #

    def handle_relay_get(self, client, method_line, headers):
        """Serve a continuous audio stream with ICY metadata for relay testing."""
        # Build ICY response headers
        response_lines = [
            "HTTP/1.0 200 OK",
            f"icy-name:{self.relay_title}",
            "icy-genre:Electronic",
            "icy-br:128",
            f"icy-metaint:{self.relay_metaint}",
            "Content-Type: audio/mpeg",
            "Server: Mock Icecast 2.5.0",
        ]
        response_header = "\r\n".join(response_lines) + "\r\n\r\n"
        client.sendall(response_header.encode())
        print(f"{GREEN}  → 200 OK (Relay mode){RESET}")
        print(f"{GREEN}  ▶ Serving audio stream with ICY metadata...{RESET}")

        # Build the ICY metadata block
        meta_block = self._build_icy_metadata(self.relay_metadata)
        session_bytes = 0
        meta_count = 0

        try:
            while self.running:
                # Send metaint bytes of silence (MP3 padding)
                silence = b"\x00" * self.relay_metaint
                client.sendall(silence)
                session_bytes += self.relay_metaint
                self.total_bytes_sent += self.relay_metaint

                # Send ICY metadata block
                client.sendall(meta_block)
                session_bytes += len(meta_block)
                self.total_bytes_sent += len(meta_block)
                meta_count += 1

                sys.stdout.write(
                    f"\r{DIM}  Relay: {session_bytes:,} bytes sent, "
                    f"{meta_count} metadata blocks{RESET}  "
                )
                sys.stdout.flush()

                # Pace the stream roughly like 128kbps
                time.sleep(self.relay_metaint / (128_000 / 8))
        except (ConnectionResetError, BrokenPipeError, OSError):
            pass

        print(f"\n{YELLOW}  ■ Relay ended: {session_bytes:,} bytes sent, "
              f"{meta_count} metadata blocks{RESET}")

    @staticmethod
    def _build_icy_metadata(title):
        """Build a padded ICY metadata block with length byte prefix.

        Format: 1 byte length N, followed by N*16 bytes of metadata
        string padded with null bytes.
        """
        meta_str = f"StreamTitle='{title}';"
        meta_bytes = meta_str.encode("utf-8")
        # Pad to next multiple of 16
        n = (len(meta_bytes) + 15) // 16
        padded = meta_bytes.ljust(n * 16, b"\x00")
        # Prefix with length byte
        return struct.pack("B", n) + padded

    # ------------------------------------------------------------------ #
    # Digest authentication                                                #
    # ------------------------------------------------------------------ #

    def _handle_digest_challenge(self, client, headers, reject_always=False):
        """Handle Digest auth flow. Returns True if the connection was handled."""
        auth_header = headers.get("authorization", "")

        if not auth_header.startswith("Digest "):
            # No Digest credentials — send 401 challenge
            challenge = (
                'Digest realm="IcecastKit", '
                'nonce="mock-nonce-12345", '
                'algorithm=MD5, '
                'qop="auth"'
            )
            response = (
                f"HTTP/1.1 401 Unauthorized\r\n"
                f"WWW-Authenticate: {challenge}\r\n"
                f"\r\n"
            )
            client.sendall(response.encode())
            self.digest_challenges_sent += 1
            print(f"{YELLOW}  → 401 + Digest challenge sent{RESET}")
            client.close()
            return True

        # Parse received Digest parameters
        params = self._parse_digest_params(auth_header)
        print(f"{DIM}  Digest params received:{RESET}")
        for k in ("username", "realm", "nonce", "uri", "response", "nc", "cnonce"):
            if k in params:
                print(f"{DIM}    {k}={params[k]}{RESET}")

        if reject_always:
            # Always reject — for testing digestAuthFailed
            challenge = (
                'Digest realm="IcecastKit", '
                'nonce="mock-nonce-99999", '
                'algorithm=MD5, '
                'qop="auth"'
            )
            response = (
                f"HTTP/1.1 401 Unauthorized\r\n"
                f"WWW-Authenticate: {challenge}\r\n"
                f"\r\n"
            )
            client.sendall(response.encode())
            self.digest_challenges_sent += 1
            print(f"{RED}  → 401 Digest always-reject{RESET}")
            client.close()
            return True

        # Accept the Digest credentials
        self.digest_auth_succeeded += 1
        print(f"{GREEN}  ✓ Digest auth accepted{RESET}")
        return False  # Let normal flow continue (200 OK + audio)

    @staticmethod
    def _parse_digest_params(auth_header):
        """Parse 'Digest key="val", key2=val2' into a dict."""
        params = {}
        # Strip "Digest " prefix
        raw = auth_header[len("Digest "):].strip()
        # Split on commas, handling quoted values
        for part in raw.split(","):
            part = part.strip()
            if "=" not in part:
                continue
            key, _, value = part.partition("=")
            key = key.strip()
            value = value.strip().strip('"')
            params[key] = value
        return params

    # ------------------------------------------------------------------ #
    # Admin API                                                            #
    # ------------------------------------------------------------------ #

    def handle_admin(self, client, method_line, headers):
        """Handle admin API requests."""
        # Check auth
        if "authorization" not in headers:
            client.sendall(b"HTTP/1.1 401 Unauthorized\r\n\r\n")
            print(f"{RED}  → 401 (no admin auth){RESET}")
            client.close()
            return

        if "/admin/metadata" in method_line:
            self.metadata_updates += 1
            # Extract song from query
            if "song=" in method_line:
                song = method_line.split("song=")[1].split(" ")[0].split("&")[0]
                from urllib.parse import unquote_plus
                song = unquote_plus(song)
                print(f"{GREEN}  → Metadata updated: \"{song}\" "
                      f"(#{self.metadata_updates}){RESET}")
            client.sendall(
                b"HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\n\r\n"
                b"<icecast><return>1</return></icecast>"
            )
            client.close()

        elif "/admin/stats" in method_line:
            mount_param = ""
            if "mount=" in method_line:
                mount_param = method_line.split("mount=")[1].split(" ")[0].split("&")[0]
                from urllib.parse import unquote
                mount_param = unquote(mount_param)

            if mount_param:
                xml = f"""<?xml version="1.0"?>
<icestats>
<source mount="{mount_param}">
<listeners>42</listeners>
<title>Test Stream - Mock Song</title>
<bitrate>128</bitrate>
<genre>Electronic</genre>
<server_type>audio/mpeg</server_type>
<connected>3600</connected>
</source>
</icestats>"""
            else:
                xml = """<?xml version="1.0"?>
<icestats>
<server_id>Mock Icecast 2.5.0</server_id>
<source mount="/live.mp3">
<listeners>42</listeners>
<title>Test Stream - Mock Song</title>
<bitrate>128</bitrate>
<genre>Electronic</genre>
<server_type>audio/mpeg</server_type>
</source>
<source mount="/backup.ogg">
<listeners>5</listeners>
<genre>Ambient</genre>
<server_type>application/ogg</server_type>
</source>
</icestats>"""

            response = (
                f"HTTP/1.1 200 OK\r\n"
                f"Content-Type: text/xml\r\n"
                f"Content-Length: {len(xml)}\r\n"
                f"\r\n{xml}"
            )
            client.sendall(response.encode())
            print(f"{GREEN}  → Stats returned"
                  f"{' for ' + mount_param if mount_param else ' (global)'}{RESET}")
            client.close()

    # ------------------------------------------------------------------ #
    # Summary                                                              #
    # ------------------------------------------------------------------ #

    def stop(self):
        """Stop the server and print a summary."""
        self.running = False
        if self.server:
            self.server.close()
        print(f"\n{YELLOW}═══ Server summary [{self.label}] ═══{RESET}")
        print(f"  Connections: {self.connections}")
        print(f"  Total audio bytes received: {self.total_bytes_received:,}")
        if self.total_bytes_sent > 0:
            print(f"  Total audio bytes sent (relay): {self.total_bytes_sent:,}")
        print(f"  Metadata updates: {self.metadata_updates}")
        if self.digest_challenges_sent > 0:
            print(f"  Digest challenges sent: {self.digest_challenges_sent}")
            print(f"  Digest auth succeeded: {self.digest_auth_succeeded}")
        if self.bearer_accepted > 0 or self.bearer_rejected > 0:
            print(f"  Bearer accepted: {self.bearer_accepted}")
            print(f"  Bearer rejected: {self.bearer_rejected}")


def run_dual_port(args, server_kwargs):
    """Run two servers concurrently on --port and --port2."""
    kwargs1 = dict(server_kwargs, port=args.port, label=f"port {args.port}")
    kwargs2 = dict(server_kwargs, port=args.port2, label=f"port {args.port2}")
    server1 = MockIcecastServer(**kwargs1)
    server2 = MockIcecastServer(**kwargs2)

    t2 = threading.Thread(target=server2.start, daemon=True)
    t2.start()

    try:
        server1.start()
    except KeyboardInterrupt:
        server1.stop()
        server2.stop()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Mock Icecast/SHOUTcast server for IcecastKit testing",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
examples:
  %(prog)s --port 8000                           Basic PUT mode
  %(prog)s --port 8000 --serve-relay              Relay mode (serve audio)
  %(prog)s --port 8000 --serve-relay \\
    --relay-metadata "Pink Floyd - Comfortably Numb" \\
    --relay-title "Classic Rock Radio"            Custom relay metadata
  %(prog)s --port 8000 --fail digest-challenge    Digest auth
  %(prog)s --port 8000 --fail digest-always-reject
  %(prog)s --port 8000 --bearer-token "my-token"  Bearer auth
  %(prog)s --port 8000 --probe-mode               Bandwidth probe
  %(prog)s --port 8000 --port2 8001               Dual-port
  %(prog)s --port 8000 --fail 401                 Simulate 401
  %(prog)s --port 8000 --fail 403-mount-in-use    Simulate 403
  %(prog)s --port 8000 --fail 500                 Simulate 500
""",
    )
    parser.add_argument(
        "--port", type=int, default=8000,
        help="Listen port (default: 8000)",
    )
    parser.add_argument(
        "--port2", type=int, default=None,
        help="Second listen port for multi-destination testing",
    )
    parser.add_argument(
        "--mode",
        choices=["icecast-put", "icecast-source", "shoutcast"],
        default="icecast-put",
        help="Server protocol mode (default: icecast-put)",
    )
    parser.add_argument(
        "--fail",
        choices=["401", "403-mount-in-use", "500",
                 "digest-challenge", "digest-always-reject"],
        default=None,
        help="Simulate an error or auth challenge",
    )
    parser.add_argument(
        "--serve-relay", action="store_true",
        help="Enable relay mode: serve audio with ICY metadata on GET",
    )
    parser.add_argument(
        "--relay-metaint", type=int, default=8192,
        help="ICY metadata interval in bytes (default: 8192)",
    )
    parser.add_argument(
        "--relay-metadata", type=str,
        default="Mock Artist - Mock Song",
        help="StreamTitle for ICY metadata (default: 'Mock Artist - Mock Song')",
    )
    parser.add_argument(
        "--relay-title", type=str, default="Mock Radio",
        help="icy-name header value (default: 'Mock Radio')",
    )
    parser.add_argument(
        "--bearer-token", type=str, default=None,
        help="Require this Bearer token for authentication",
    )
    parser.add_argument(
        "--probe-mode", action="store_true",
        help="Probe mode: accept audio then disconnect after --probe-duration",
    )
    parser.add_argument(
        "--probe-duration", type=float, default=3.0,
        help="Seconds before disconnecting in probe mode (default: 3.0)",
    )
    args = parser.parse_args()

    server_kwargs = dict(
        mode=args.mode,
        fail_mode=args.fail,
        serve_relay=args.serve_relay,
        relay_metaint=args.relay_metaint,
        relay_metadata=args.relay_metadata,
        relay_title=args.relay_title,
        bearer_token=args.bearer_token,
        probe_mode=args.probe_mode,
        probe_duration=args.probe_duration,
    )

    if args.port2:
        run_dual_port(args, server_kwargs)
    else:
        server = MockIcecastServer(port=args.port, **server_kwargs)
        try:
            server.start()
        except KeyboardInterrupt:
            server.stop()
