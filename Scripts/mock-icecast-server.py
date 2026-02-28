#!/usr/bin/env python3
"""Mock Icecast/SHOUTcast server for manual CLI testing."""

import socket
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
    def __init__(self, port=8000, mode="icecast-put", fail_mode=None):
        self.port = port
        self.mode = mode
        self.fail_mode = fail_mode
        self.server = None
        self.running = False
        self.total_bytes = 0
        self.connections = 0
        self.metadata_updates = 0

    def start(self):
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(("0.0.0.0", self.port))
        self.server.listen(5)
        self.server.settimeout(1.0)
        self.running = True
        print(f"{GREEN}▶ Mock server started on port {self.port} (mode: {self.mode}){RESET}")
        if self.fail_mode:
            print(f"{YELLOW}  Fail mode: {self.fail_mode}{RESET}")
        print(f"{DIM}  Ctrl+C to stop{RESET}\n")

        while self.running:
            try:
                client, addr = self.server.accept()
                self.connections += 1
                print(f"{CYAN}← Connection #{self.connections} from {addr[0]}:{addr[1]}{RESET}")
                t = threading.Thread(target=self.handle_client, args=(client, addr))
                t.daemon = True
                t.start()
            except socket.timeout:
                continue
            except OSError:
                break

    def handle_client(self, client, addr):
        try:
            # Read initial request
            data = b""
            while b"\r\n\r\n" not in data:
                chunk = client.recv(4096)
                if not chunk:
                    return
                data += chunk

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

            # --- SHOUTcast (password line) ---
            else:
                # Could be shoutcast password
                password_line = method_line.strip()
                print(f"{DIM}  SHOUTcast password received: {password_line}{RESET}")
                client.sendall(b"OK2\r\nicy-caps:11\r\n\r\n")
                print(f"{GREEN}  → OK2 (SHOUTcast){RESET}")
                # Read headers after auth
                header_data = b""
                while b"\r\n\r\n" not in header_data:
                    chunk = client.recv(4096)
                    if not chunk:
                        return
                    header_data += chunk
                sc_headers = header_data.decode("utf-8", errors="replace")
                print(f"{DIM}  SHOUTcast headers received ({len(sc_headers)} bytes){RESET}")
                self.receive_audio(client)

        except Exception as e:
            print(f"{RED}  Error: {e}{RESET}")
        finally:
            try:
                client.close()
            except:
                pass

    def receive_audio(self, client):
        """Receive and count audio data bytes."""
        print(f"{GREEN}  ▶ Receiving audio stream...{RESET}")
        session_bytes = 0
        start = time.time()
        try:
            while self.running:
                data = client.recv(8192)
                if not data:
                    break
                session_bytes += len(data)
                self.total_bytes += len(data)
                elapsed = time.time() - start
                rate = (session_bytes * 8 / 1000 / max(elapsed, 0.001))
                sys.stdout.write(f"\r{DIM}  Audio: {session_bytes:,} bytes ({elapsed:.1f}s, {rate:.0f} kbps){RESET}  ")
                sys.stdout.flush()
        except (ConnectionResetError, BrokenPipeError):
            pass
        print(f"\n{YELLOW}  ■ Stream ended: {session_bytes:,} bytes received{RESET}")

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
                print(f"{GREEN}  → Metadata updated: \"{song}\" (#{self.metadata_updates}){RESET}")
            client.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\n\r\n<icecast><return>1</return></icecast>")
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

            response = f"HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\nContent-Length: {len(xml)}\r\n\r\n{xml}"
            client.sendall(response.encode())
            print(f"{GREEN}  → Stats returned{' for ' + mount_param if mount_param else ' (global)'}{RESET}")
            client.close()

    def stop(self):
        self.running = False
        if self.server:
            self.server.close()
        print(f"\n{YELLOW}═══ Server summary ═══{RESET}")
        print(f"  Connections: {self.connections}")
        print(f"  Total audio bytes: {self.total_bytes:,}")
        print(f"  Metadata updates: {self.metadata_updates}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Mock Icecast server")
    parser.add_argument("--port", type=int, default=8000, help="Listen port")
    parser.add_argument("--mode", choices=["icecast-put", "icecast-source", "shoutcast"], default="icecast-put")
    parser.add_argument("--fail", choices=["401", "403-mount-in-use", "500"], default=None, help="Simulate error")
    args = parser.parse_args()

    server = MockIcecastServer(port=args.port, mode=args.mode, fail_mode=args.fail)
    try:
        server.start()
    except KeyboardInterrupt:
        server.stop()
