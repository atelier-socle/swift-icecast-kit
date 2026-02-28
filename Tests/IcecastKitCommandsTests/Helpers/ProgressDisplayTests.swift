// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKitCommands

@Suite("ProgressDisplay")
struct ProgressDisplayTests {

    @Test("formatBytes 0 produces 0 B")
    func formatBytesZero() {
        #expect(ProgressDisplay.formatBytes(0) == "0 B")
    }

    @Test("formatBytes 1023 produces 1023 B")
    func formatBytes1023() {
        #expect(ProgressDisplay.formatBytes(1023) == "1023 B")
    }

    @Test("formatBytes 1024 produces 1.0 KB")
    func formatBytes1024() {
        #expect(ProgressDisplay.formatBytes(1024) == "1.0 KB")
    }

    @Test("formatBytes 1048576 produces 1.0 MB")
    func formatBytes1MB() {
        #expect(ProgressDisplay.formatBytes(1_048_576) == "1.0 MB")
    }

    @Test("formatBytes 1073741824 produces 1.0 GB")
    func formatBytes1GB() {
        #expect(ProgressDisplay.formatBytes(1_073_741_824) == "1.0 GB")
    }

    @Test("formatDuration 0 produces 00:00:00")
    func formatDurationZero() {
        #expect(ProgressDisplay.formatDuration(0) == "00:00:00")
    }

    @Test("formatDuration 65 produces 00:01:05")
    func formatDuration65() {
        #expect(ProgressDisplay.formatDuration(65) == "00:01:05")
    }

    @Test("formatDuration 3661 produces 01:01:01")
    func formatDuration3661() {
        #expect(ProgressDisplay.formatDuration(3661) == "01:01:01")
    }

    @Test("formatBitrate 128000 produces 128.0 kbps")
    func formatBitrate128k() {
        #expect(ProgressDisplay.formatBitrate(128_000) == "128.0 kbps")
    }

    @Test("formatConnected includes host, port, mountpoint, protocol")
    func formatConnectedIncludesAll() {
        let display = ProgressDisplay(color: ColorOutput(noColor: true))
        let result = display.formatConnected(host: "radio.test", port: 8000, mountpoint: "/live", protocolName: "Icecast PUT")
        #expect(result.contains("radio.test"))
        #expect(result.contains("8000"))
        #expect(result.contains("/live"))
        #expect(result.contains("Icecast PUT"))
    }

    @Test("formatReconnecting includes attempt number and delay")
    func formatReconnectingIncludesInfo() {
        let display = ProgressDisplay(color: ColorOutput(noColor: true))
        let result = display.formatReconnecting(attempt: 2, maxRetries: 10, delay: 4.0)
        #expect(result.contains("3/10"))
        #expect(result.contains("4.0"))
    }

    @Test("formatError wraps message")
    func formatErrorWrapsMessage() {
        let display = ProgressDisplay(color: ColorOutput(noColor: true))
        let result = display.formatError("connection refused")
        #expect(result.contains("Error"))
        #expect(result.contains("connection refused"))
    }

    @Test("formatStreamingStatus includes all components")
    func formatStreamingStatusIncludesAll() {
        let display = ProgressDisplay(color: ColorOutput(noColor: true))
        let result = display.formatStreamingStatus(elapsed: 332, bytesSent: 2_500_000, bitrate: 128_000, title: "Artist - Song")
        #expect(result.contains("Streaming"))
        #expect(result.contains("00:05:32"))
        #expect(result.contains("MB"))
        #expect(result.contains("kbps"))
        #expect(result.contains("Artist - Song"))
    }
}
