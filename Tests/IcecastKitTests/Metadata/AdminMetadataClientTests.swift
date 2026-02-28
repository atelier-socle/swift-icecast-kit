// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("AdminMetadataClient")
struct AdminMetadataClientTests {

    let adminCreds = IcecastCredentials(username: "admin", password: "hackme")

    func makeClient(mock: MockTransportConnection) -> AdminMetadataClient {
        AdminMetadataClient(
            host: "radio.example.com",
            port: 8000,
            useTLS: false,
            credentials: adminCreds,
            connectionFactory: { mock }
        )
    }

    func httpResponse(status: Int, message: String, body: String = "") -> Data {
        let headers = "HTTP/1.1 \(status) \(message)\r\nContent-Type: text/xml\r\n\r\n"
        return Data((headers + body).utf8)
    }

    // MARK: - Metadata Update

    @Test("Correct GET request built for /admin/metadata")
    func metadataUpdateRequest() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK"))
        let client = makeClient(mock: mock)

        let metadata = ICYMetadata(streamTitle: "Artist - Song")
        try await client.updateMetadata(metadata, mountpoint: "/live.mp3")

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)

        #expect(request.contains("GET /admin/metadata?"))
    }

    @Test("mount parameter matches mountpoint")
    func metadataUpdateMountParam() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK"))
        let client = makeClient(mock: mock)

        try await client.updateMetadata(
            ICYMetadata(streamTitle: "Song"), mountpoint: "/live.mp3")

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)

        #expect(request.contains("mount=/live.mp3"))
    }

    @Test("mode=updinfo always present")
    func metadataUpdateModeParam() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK"))
        let client = makeClient(mock: mock)

        try await client.updateMetadata(
            ICYMetadata(streamTitle: "Song"), mountpoint: "/live.mp3")

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)

        #expect(request.contains("mode=updinfo"))
    }

    @Test("song parameter is URL-encoded")
    func metadataUpdateSongEncoded() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK"))
        let client = makeClient(mock: mock)

        try await client.updateMetadata(
            ICYMetadata(streamTitle: "Artist - Song"), mountpoint: "/live.mp3")

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)

        #expect(request.contains("song=Artist+-+Song"))
    }

    @Test("Authorization header uses admin credentials")
    func metadataUpdateAuth() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK"))
        let client = makeClient(mock: mock)

        try await client.updateMetadata(
            ICYMetadata(streamTitle: "Song"), mountpoint: "/live.mp3")

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)

        #expect(request.contains("Authorization: \(adminCreds.basicAuthHeaderValue())"))
    }

    @Test("Host header correct")
    func metadataUpdateHost() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK"))
        let client = makeClient(mock: mock)

        try await client.updateMetadata(
            ICYMetadata(streamTitle: "Song"), mountpoint: "/live.mp3")

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)

        #expect(request.contains("Host: radio.example.com:8000"))
    }

    @Test("Connection: close header present")
    func metadataUpdateConnectionClose() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK"))
        let client = makeClient(mock: mock)

        try await client.updateMetadata(
            ICYMetadata(streamTitle: "Song"), mountpoint: "/live.mp3")

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)

        #expect(request.contains("Connection: close"))
    }

    @Test("200 OK → success")
    func metadataUpdate200() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK"))
        let client = makeClient(mock: mock)

        try await client.updateMetadata(
            ICYMetadata(streamTitle: "Song"), mountpoint: "/live.mp3")
        // No error = success
    }

    @Test("401 → throws authenticationFailed")
    func metadataUpdate401() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 401, message: "Unauthorized"))
        let client = makeClient(mock: mock)

        do {
            try await client.updateMetadata(
                ICYMetadata(streamTitle: "Song"), mountpoint: "/live.mp3")
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .authenticationFailed = error {
                // Expected
            } else {
                Issue.record("Expected authenticationFailed, got \(error)")
            }
        }
    }

    @Test("404 → throws adminAPIUnavailable")
    func metadataUpdate404() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 404, message: "Not Found"))
        let client = makeClient(mock: mock)

        do {
            try await client.updateMetadata(
                ICYMetadata(streamTitle: "Song"), mountpoint: "/live.mp3")
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .adminAPIUnavailable = error {
                // Expected
            } else {
                Issue.record("Expected adminAPIUnavailable, got \(error)")
            }
        }
    }

    @Test("500 → throws serverError")
    func metadataUpdate500() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            httpResponse(status: 500, message: "Internal Server Error"))
        let client = makeClient(mock: mock)

        do {
            try await client.updateMetadata(
                ICYMetadata(streamTitle: "Song"), mountpoint: "/live.mp3")
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .serverError = error {
                // Expected
            } else {
                Issue.record("Expected serverError, got \(error)")
            }
        }
    }

    @Test("Nil streamTitle → throws metadataUpdateFailed")
    func metadataUpdateNilTitle() async throws {
        let mock = MockTransportConnection()
        let client = makeClient(mock: mock)

        await #expect(throws: IcecastError.self) {
            try await client.updateMetadata(ICYMetadata(), mountpoint: "/live.mp3")
        }
    }

    // MARK: - Server Stats

    @Test("Correct GET request for /admin/stats")
    func serverStatsRequest() async throws {
        let xml = """
            <?xml version="1.0"?>
            <icestats>
                <server_id>Icecast 2.5.0</server_id>
            </icestats>
            """
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK", body: xml))
        let client = makeClient(mock: mock)

        _ = try await client.fetchServerStats()

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)

        #expect(request.contains("GET /admin/stats HTTP/1.1"))
    }

    @Test("Server version extracted from server_id")
    func serverStatsVersion() async throws {
        let xml = """
            <?xml version="1.0"?>
            <icestats>
                <server_id>Icecast 2.5.0</server_id>
            </icestats>
            """
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK", body: xml))
        let client = makeClient(mock: mock)

        let stats = try await client.fetchServerStats()
        #expect(stats.serverVersion == "Icecast 2.5.0")
    }

    @Test("Multiple mountpoints listed")
    func serverStatsMultipleMounts() async throws {
        let xml = """
            <?xml version="1.0"?>
            <icestats>
                <server_id>Icecast 2.5.0</server_id>
                <source mount="/live.mp3">
                    <listeners>42</listeners>
                </source>
                <source mount="/backup.ogg">
                    <listeners>5</listeners>
                </source>
            </icestats>
            """
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK", body: xml))
        let client = makeClient(mock: mock)

        let stats = try await client.fetchServerStats()
        #expect(stats.activeMountpoints.count == 2)
        #expect(stats.activeMountpoints.contains("/live.mp3"))
        #expect(stats.activeMountpoints.contains("/backup.ogg"))
    }

    @Test("Listener counts summed")
    func serverStatsListenerCount() async throws {
        let xml = """
            <?xml version="1.0"?>
            <icestats>
                <source mount="/live.mp3">
                    <listeners>42</listeners>
                </source>
                <source mount="/backup.ogg">
                    <listeners>5</listeners>
                </source>
            </icestats>
            """
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK", body: xml))
        let client = makeClient(mock: mock)

        let stats = try await client.fetchServerStats()
        #expect(stats.totalListeners == 47)
    }

    @Test("Source count correct")
    func serverStatsSourceCount() async throws {
        let xml = """
            <?xml version="1.0"?>
            <icestats>
                <source mount="/live.mp3">
                    <listeners>10</listeners>
                </source>
                <source mount="/backup.ogg">
                    <listeners>5</listeners>
                </source>
            </icestats>
            """
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK", body: xml))
        let client = makeClient(mock: mock)

        let stats = try await client.fetchServerStats()
        #expect(stats.totalSources == 2)
    }

    @Test("Empty XML → default values")
    func serverStatsEmptyXML() async throws {
        let xml = "<?xml version=\"1.0\"?><icestats></icestats>"
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK", body: xml))
        let client = makeClient(mock: mock)

        let stats = try await client.fetchServerStats()
        #expect(stats.serverVersion == "")
        #expect(stats.activeMountpoints.isEmpty)
        #expect(stats.totalListeners == 0)
    }

    @Test("Server stats 401 → throws authenticationFailed")
    func serverStats401() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 401, message: "Unauthorized"))
        let client = makeClient(mock: mock)

        await #expect(throws: IcecastError.self) {
            try await client.fetchServerStats()
        }
    }

    // MARK: - Mount Stats

    @Test("Correct GET request for /admin/stats?mount=/live.mp3")
    func mountStatsRequest() async throws {
        let xml = """
            <?xml version="1.0"?>
            <icestats>
                <source mount="/live.mp3">
                    <listeners>42</listeners>
                </source>
            </icestats>
            """
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK", body: xml))
        let client = makeClient(mock: mock)

        _ = try await client.fetchMountStats(mountpoint: "/live.mp3")

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)

        #expect(request.contains("GET /admin/stats?mount=/live.mp3"))
    }

    @Test("All fields extracted from XML")
    func mountStatsAllFields() async throws {
        let xml = """
            <?xml version="1.0"?>
            <icestats>
                <source mount="/live.mp3">
                    <listeners>42</listeners>
                    <title>Artist - Song</title>
                    <bitrate>128</bitrate>
                    <genre>Rock</genre>
                    <server_type>audio/mpeg</server_type>
                    <connected>3600</connected>
                </source>
            </icestats>
            """
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK", body: xml))
        let client = makeClient(mock: mock)

        let stats = try await client.fetchMountStats(mountpoint: "/live.mp3")
        #expect(stats.mountpoint == "/live.mp3")
        #expect(stats.listeners == 42)
        #expect(stats.streamTitle == "Artist - Song")
        #expect(stats.bitrate == 128)
        #expect(stats.genre == "Rock")
        #expect(stats.contentType == "audio/mpeg")
        #expect(stats.connectedDuration == 3600)
    }

    @Test("Missing optional fields → nil")
    func mountStatsMissingFields() async throws {
        let xml = """
            <?xml version="1.0"?>
            <icestats>
                <source mount="/live.mp3">
                    <listeners>10</listeners>
                </source>
            </icestats>
            """
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK", body: xml))
        let client = makeClient(mock: mock)

        let stats = try await client.fetchMountStats(mountpoint: "/live.mp3")
        #expect(stats.listeners == 10)
        #expect(stats.streamTitle == nil)
        #expect(stats.bitrate == nil)
        #expect(stats.genre == nil)
        #expect(stats.contentType == nil)
        #expect(stats.connectedDuration == nil)
    }

    @Test("Mountpoint not found → throws mountpointNotFound")
    func mountStatsNotFound() async throws {
        let xml = """
            <?xml version="1.0"?>
            <icestats>
                <source mount="/other.mp3">
                    <listeners>5</listeners>
                </source>
            </icestats>
            """
        let mock = MockTransportConnection()
        await mock.enqueueResponse(httpResponse(status: 200, message: "OK", body: xml))
        let client = makeClient(mock: mock)

        do {
            _ = try await client.fetchMountStats(mountpoint: "/live.mp3")
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .mountpointNotFound = error {
                // Expected
            } else {
                Issue.record("Expected mountpointNotFound, got \(error)")
            }
        }
    }

    // MARK: - Stats Models

    @Test("ServerStats init with defaults")
    func serverStatsDefaults() {
        let stats = ServerStats()
        #expect(stats.serverVersion == "")
        #expect(stats.activeMountpoints.isEmpty)
        #expect(stats.totalListeners == 0)
        #expect(stats.totalSources == 0)
    }

    @Test("MountStats init with defaults")
    func mountStatsDefaults() {
        let stats = MountStats(mountpoint: "/live.mp3")
        #expect(stats.mountpoint == "/live.mp3")
        #expect(stats.listeners == 0)
        #expect(stats.streamTitle == nil)
    }

    @Test("ServerStats is Hashable")
    func serverStatsHashable() {
        let a = ServerStats(serverVersion: "1.0")
        let b = ServerStats(serverVersion: "1.0")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("MountStats is Hashable")
    func mountStatsHashable() {
        let a = MountStats(mountpoint: "/live.mp3", listeners: 10)
        let b = MountStats(mountpoint: "/live.mp3", listeners: 10)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
