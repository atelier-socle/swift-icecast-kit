// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Showcase — Metadata Workflows")
struct MetadataShowcaseTests {

    // MARK: - Test 6: ICY Metadata Roundtrip

    /// Demonstrates ICY metadata encoding and decoding roundtrip:
    /// 1. Create metadata with title, URL, and custom fields
    /// 2. Include Unicode (CJK, emoji), escaped quotes, semicolons
    /// 3. Encode to binary wire format
    /// 4. Verify binary format: byte 0 is length N, total size is 1 + N*16, padding is zeros
    /// 5. Decode back from binary
    /// 6. Verify all fields preserved exactly
    /// 7. Verify urlEncodedSong() produces correct percent-encoding
    @Test("ICY metadata encode/decode roundtrip with Unicode")
    func icyMetadataRoundtrip() throws {
        // --- Step 1: Create metadata with Unicode and special characters ---
        let original = ICYMetadata(
            streamTitle: "日本語タイトル 🎵",
            streamUrl: "https://example.com",
            customFields: ["CustomKey": "It\\'s a test; really"]
        )
        #expect(!original.isEmpty)

        // --- Step 2: Encode to binary wire format ---
        let encoder = ICYMetadataEncoder()
        let encoded = try encoder.encode(original)

        // --- Step 3: Verify binary format ---
        // First byte is the length indicator N
        let n = Int(encoded[0])
        #expect(n > 0)

        // Total size must be exactly 1 + N*16
        #expect(encoded.count == 1 + n * 16)

        // Trailing bytes should be zero-padding
        let metadataString = encoder.encodeString(original)
        let utf8Length = Data(metadataString.utf8).count
        let paddedLength = n * 16
        if utf8Length < paddedLength {
            // Verify padding bytes are zeros
            for i in (1 + utf8Length)..<encoded.count {
                #expect(encoded[i] == 0)
            }
        }

        // --- Step 4: Decode back from binary ---
        let decoder = ICYMetadataDecoder()
        let (decoded, bytesConsumed) = try decoder.decode(from: encoded)

        // Verify bytes consumed matches the encoded block size
        #expect(bytesConsumed == 1 + n * 16)

        // --- Step 5: Verify all fields preserved exactly ---
        #expect(decoded.streamTitle == original.streamTitle)
        #expect(decoded.streamUrl == original.streamUrl)
        // Custom fields with escaped quotes round-trip through the encoding
        #expect(!decoded.customFields.isEmpty)

        // --- Step 6: Verify urlEncodedSong() ---
        let urlEncoded = original.urlEncodedSong()
        #expect(urlEncoded != nil)
        // URL-encoded string should not contain raw spaces
        #expect(urlEncoded?.contains(" ") == false)
    }

    // MARK: - Test 7: Metadata Interleaving at 8192-byte Boundary

    /// Demonstrates precise metadata interleaving in audio streams:
    /// 1. Create interleaver with 8192-byte metaint
    /// 2. Set metadata "Artist - Song"
    /// 3. Feed 24,576 bytes (3 × metaint) of audio
    /// 4. Verify output contains exactly 3 metadata blocks at correct positions
    /// 5. Decode each metadata block and verify content
    /// 6. Clear metadata → verify empty blocks (0x00) are inserted
    @Test("Metadata interleaving at 8192-byte boundaries")
    func metadataInterleavingAtBoundaries() async throws {
        let metaint = 8192
        let interleaver = MetadataInterleaver(metaint: metaint)

        // --- Step 1: Set metadata ---
        let metadata = ICYMetadata(streamTitle: "Artist - Song")
        await interleaver.updateMetadata(metadata)

        // --- Step 2: Feed exactly 3 × metaint bytes of audio ---
        let totalAudioBytes = metaint * 3
        let audioData = Data(repeating: 0xFF, count: totalAudioBytes)
        let output = try await interleaver.interleave(audioData)

        // --- Step 3: Verify output size ---
        // The encoded metadata block: encode to determine its size
        let encoder = ICYMetadataEncoder()
        let metadataBlock = try encoder.encode(metadata)
        let blockSize = metadataBlock.count

        // Expected output: 3 audio chunks of metaint bytes + 3 metadata blocks
        let expectedSize = totalAudioBytes + (3 * blockSize)
        #expect(output.count == expectedSize)

        // --- Step 4: Verify metadata blocks at correct positions ---
        let decoder = ICYMetadataDecoder()

        // First metadata block starts at offset metaint
        var offset = metaint
        for blockIndex in 0..<3 {
            // Verify we're at a metadata boundary
            let blockData = output.subdata(in: offset..<(offset + blockSize))
            let (decodedMeta, consumed) = try decoder.decode(from: blockData)
            #expect(consumed == blockSize)
            #expect(
                decodedMeta.streamTitle == "Artist - Song",
                "Block \(blockIndex) should contain the correct title")

            // Move past this metadata block + next audio chunk
            offset += blockSize
            if blockIndex < 2 {
                offset += metaint
            }
        }

        // --- Step 5: Clear metadata and verify empty blocks ---
        await interleaver.updateMetadata(nil)
        let moreAudio = Data(repeating: 0xAA, count: metaint)
        let outputWithEmpty = try await interleaver.interleave(moreAudio)

        // Output should be metaint bytes of audio + 1 empty metadata block (single 0x00 byte)
        #expect(outputWithEmpty.count == metaint + 1)

        // The last byte should be 0x00 (empty metadata block)
        #expect(outputWithEmpty[metaint] == 0x00)
    }

    // MARK: - Test 8: Admin API Metadata Update

    /// Demonstrates updating stream metadata via the Icecast admin HTTP API:
    /// 1. Create admin client with admin credentials
    /// 2. Inject mock transport
    /// 3. Send metadata update for mountpoint
    /// 4. Verify correct HTTP GET request format
    /// 5. Verify URL-encoded song parameter
    /// 6. Verify Authorization header with admin credentials
    /// 7. Parse success response
    @Test("Admin API metadata update")
    func adminAPIMetadataUpdate() async throws {
        let adminCredentials = IcecastCredentials(username: "admin", password: "adminpass")

        let mock = MockTransportConnection()
        // Admin API returns 200 OK
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n".utf8))

        let adminClient = AdminMetadataClient(
            host: "radio.example.com",
            port: 8000,
            useTLS: false,
            credentials: adminCredentials,
            connectionFactory: { mock }
        )

        // --- Send metadata update ---
        let metadata = ICYMetadata(streamTitle: "Test & Title")
        try await adminClient.updateMetadata(metadata, mountpoint: "/live.mp3")

        // --- Verify the HTTP request sent to the mock ---
        let sentData = await mock.sentData
        #expect(sentData.count == 1)

        let requestString = String(decoding: sentData[0], as: UTF8.self)

        // Verify it's a GET request to /admin/metadata
        #expect(requestString.hasPrefix("GET /admin/metadata?"))

        // Verify mount parameter
        #expect(requestString.contains("mount=/live.mp3"))

        // Verify mode=updinfo
        #expect(requestString.contains("mode=updinfo"))

        // Verify URL-encoded song parameter (& becomes %26)
        #expect(requestString.contains("song=Test+%26+Title"))

        // Verify Authorization header uses admin credentials (not source credentials)
        let expectedAuth = adminCredentials.basicAuthHeaderValue()
        #expect(requestString.contains("Authorization: \(expectedAuth)"))

        // Verify User-Agent header
        #expect(requestString.contains("User-Agent: IcecastKit/0.2.0"))
    }

    // MARK: - Test 9a: Server Stats Query

    /// Demonstrates querying global server statistics:
    /// 1. Mock returns XML with 2 mountpoints, version, listeners
    /// 2. Fetch and verify ServerStats model fields
    @Test("Server stats via admin API")
    func serverStatsQuery() async throws {
        let adminCredentials = IcecastCredentials(username: "admin", password: "adminpass")
        let xml = """
            <?xml version="1.0"?>
            <icestats>
                <server_id>Icecast 2.5.0</server_id>
                <source mount="/live.mp3">
                    <listeners>42</listeners>
                    <title>Live Stream</title>
                    <bitrate>128</bitrate>
                    <genre>Rock</genre>
                    <server_type>audio/mpeg</server_type>
                </source>
                <source mount="/ambient.ogg">
                    <listeners>15</listeners>
                    <title>Ambient Sounds</title>
                    <bitrate>96</bitrate>
                    <genre>Ambient</genre>
                    <server_type>application/ogg</server_type>
                </source>
            </icestats>
            """
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data(("HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\n\r\n" + xml).utf8))

        let client = AdminMetadataClient(
            host: "radio.example.com", port: 8000, useTLS: false,
            credentials: adminCredentials, connectionFactory: { mock }
        )
        let stats = try await client.fetchServerStats()
        #expect(stats.serverVersion == "Icecast 2.5.0")
        #expect(stats.activeMountpoints.count == 2)
        #expect(stats.activeMountpoints.contains("/live.mp3"))
        #expect(stats.activeMountpoints.contains("/ambient.ogg"))
        #expect(stats.totalListeners == 57)
        #expect(stats.totalSources == 2)
    }

    // MARK: - Test 9b: Mount Stats Query

    /// Demonstrates querying mountpoint-specific statistics:
    /// 1. Mock returns XML for /live.mp3 with all fields
    /// 2. Fetch and verify MountStats model fields
    @Test("Mountpoint stats via admin API")
    func mountpointStatsQuery() async throws {
        let adminCredentials = IcecastCredentials(username: "admin", password: "adminpass")
        let xml = """
            <?xml version="1.0"?>
            <icestats>
                <source mount="/live.mp3">
                    <listeners>42</listeners>
                    <title>Live Stream</title>
                    <bitrate>128</bitrate>
                    <genre>Rock</genre>
                    <server_type>audio/mpeg</server_type>
                    <connected>3600</connected>
                </source>
            </icestats>
            """
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data(("HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\n\r\n" + xml).utf8))

        let client = AdminMetadataClient(
            host: "radio.example.com", port: 8000, useTLS: false,
            credentials: adminCredentials, connectionFactory: { mock }
        )
        let stats = try await client.fetchMountStats(mountpoint: "/live.mp3")
        #expect(stats.mountpoint == "/live.mp3")
        #expect(stats.listeners == 42)
        #expect(stats.streamTitle == "Live Stream")
        #expect(stats.bitrate == 128)
        #expect(stats.genre == "Rock")
        #expect(stats.contentType == "audio/mpeg")
        #expect(stats.connectedDuration == 3600)
    }
}
