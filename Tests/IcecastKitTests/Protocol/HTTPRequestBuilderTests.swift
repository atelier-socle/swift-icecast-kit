// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("HTTP Request Builder")
struct HTTPRequestBuilderTests {

    let builder = HTTPRequestBuilder()
    let credentials = IcecastCredentials(password: "hackme")
    let station = StationInfo(
        name: "My Radio Station",
        description: "The best radio in town",
        url: "https://mystation.com",
        genre: "Rock;Alternative",
        isPublic: true,
        bitrate: 128,
        sampleRate: 44100,
        channels: 2
    )

    // MARK: - Icecast PUT

    @Test("PUT request has correct HTTP method and path")
    func putMethodAndPath() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "radio.example.com", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.hasPrefix("PUT /live.mp3 HTTP/1.1\r\n"))
    }

    @Test("PUT request includes Host header with port")
    func putHostHeader() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "radio.example.com", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("Host: radio.example.com:8000\r\n"))
    }

    @Test("PUT request includes Authorization header with correct Base64")
    func putAuthorizationHeader() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        let expectedAuth = credentials.basicAuthHeaderValue()
        #expect(request.contains("Authorization: \(expectedAuth)\r\n"))
    }

    @Test("PUT request includes correct Content-Type")
    func putContentType() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("Content-Type: audio/mpeg\r\n"))
    }

    @Test("PUT request includes User-Agent header")
    func putUserAgent() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("User-Agent: IcecastKit/0.2.0\r\n"))
    }

    @Test("PUT request includes Expect 100-continue")
    func putExpectContinue() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("Expect: 100-continue\r\n"))
    }

    @Test("PUT request has no Content-Length header")
    func putNoContentLength() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(!request.contains("Content-Length"))
    }

    @Test("PUT request has no Transfer-Encoding header")
    func putNoTransferEncoding() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(!request.contains("Transfer-Encoding"))
    }

    @Test("PUT request includes ice-name header")
    func putIceName() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("ice-name: My Radio Station\r\n"))
    }

    @Test("PUT request includes ice-description header")
    func putIceDescription() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("ice-description: The best radio in town\r\n"))
    }

    @Test("PUT request includes ice-url header")
    func putIceURL() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("ice-url: https://mystation.com\r\n"))
    }

    @Test("PUT request includes ice-genre header")
    func putIceGenre() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("ice-genre: Rock;Alternative\r\n"))
    }

    @Test("PUT request includes ice-public header")
    func putIcePublic() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("ice-public: 1\r\n"))
    }

    @Test("PUT request includes ice-audio-info header")
    func putIceAudioInfo() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("ice-audio-info: ice-channels=2;ice-samplerate=44100;ice-bitrate=128\r\n"))
    }

    @Test("PUT request omits ice-audio-info when no audio info")
    func putOmitsAudioInfoWhenEmpty() {
        let emptyStation = StationInfo(name: "Test", isPublic: false)
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: emptyStation
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(!request.contains("ice-audio-info"))
    }

    @Test("PUT request omits nil station fields")
    func putOmitsNilFields() {
        let minimal = StationInfo(isPublic: false)
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: minimal
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(!request.contains("ice-name"))
        #expect(!request.contains("ice-description"))
        #expect(!request.contains("ice-url"))
        #expect(!request.contains("ice-genre"))
        #expect(request.contains("ice-public: 0"))
    }

    @Test("PUT request ends with double CRLF")
    func putEndsWithDoubleCRLF() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.hasSuffix("\r\n\r\n"))
    }

    @Test("PUT request with custom port in Host header")
    func putCustomPort() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "radio.example.com", port: 9000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("Host: radio.example.com:9000\r\n"))
    }

    // MARK: - Icecast SOURCE

    @Test("SOURCE request has correct method and ICE/1.0 protocol")
    func sourceMethodAndProtocol() {
        let data = builder.buildIcecastSOURCE(
            mountpoint: "/live.mp3", credentials: credentials,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.hasPrefix("SOURCE /live.mp3 ICE/1.0\r\n"))
    }

    @Test("SOURCE request has no Expect header")
    func sourceNoExpect() {
        let data = builder.buildIcecastSOURCE(
            mountpoint: "/live.mp3", credentials: credentials,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(!request.contains("Expect"))
    }

    @Test("SOURCE request includes ice headers")
    func sourceIncludesIceHeaders() {
        let data = builder.buildIcecastSOURCE(
            mountpoint: "/live.mp3", credentials: credentials,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("ice-name: My Radio Station"))
        #expect(request.contains("ice-public: 1"))
    }

    @Test("SOURCE request ends with double CRLF")
    func sourceEndsWithDoubleCRLF() {
        let data = builder.buildIcecastSOURCE(
            mountpoint: "/live.mp3", credentials: credentials,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.hasSuffix("\r\n\r\n"))
    }

    // MARK: - SHOUTcast v1

    @Test("SHOUTcast v1 auth sends password followed by CRLF")
    func shoutcastV1Auth() {
        let data = builder.buildShoutcastV1Auth(password: "mypassword")
        let str = String(decoding: data, as: UTF8.self)
        #expect(str == "mypassword\r\n")
    }

    @Test("SHOUTcast headers include content-type")
    func shoutcastHeadersContentType() {
        let data = builder.buildShoutcastHeaders(contentType: .mp3, stationInfo: station)
        let str = String(decoding: data, as: UTF8.self)
        #expect(str.contains("content-type: audio/mpeg\r\n"))
    }

    @Test("SHOUTcast headers include icy-name")
    func shoutcastHeadersIcyName() {
        let data = builder.buildShoutcastHeaders(contentType: .mp3, stationInfo: station)
        let str = String(decoding: data, as: UTF8.self)
        #expect(str.contains("icy-name: My Radio Station\r\n"))
    }

    @Test("SHOUTcast headers include icy-genre")
    func shoutcastHeadersIcyGenre() {
        let data = builder.buildShoutcastHeaders(contentType: .mp3, stationInfo: station)
        let str = String(decoding: data, as: UTF8.self)
        #expect(str.contains("icy-genre: Rock;Alternative\r\n"))
    }

    @Test("SHOUTcast headers include icy-pub")
    func shoutcastHeadersIcyPub() {
        let data = builder.buildShoutcastHeaders(contentType: .mp3, stationInfo: station)
        let str = String(decoding: data, as: UTF8.self)
        #expect(str.contains("icy-pub: 1\r\n"))
    }

    @Test("SHOUTcast headers include icy-br")
    func shoutcastHeadersIcyBr() {
        let data = builder.buildShoutcastHeaders(contentType: .mp3, stationInfo: station)
        let str = String(decoding: data, as: UTF8.self)
        #expect(str.contains("icy-br: 128\r\n"))
    }

    @Test("SHOUTcast headers omit missing fields")
    func shoutcastHeadersOmitMissing() {
        let minimal = StationInfo(isPublic: false)
        let data = builder.buildShoutcastHeaders(contentType: .mp3, stationInfo: minimal)
        let str = String(decoding: data, as: UTF8.self)
        #expect(!str.contains("icy-name"))
        #expect(!str.contains("icy-genre"))
        #expect(!str.contains("icy-br"))
        #expect(str.contains("icy-pub: 0"))
    }

    @Test("SHOUTcast headers end with double CRLF")
    func shoutcastHeadersEndWithDoubleCRLF() {
        let data = builder.buildShoutcastHeaders(contentType: .mp3, stationInfo: station)
        let str = String(decoding: data, as: UTF8.self)
        #expect(str.hasSuffix("\r\n\r\n"))
    }

    // MARK: - Content Types

    @Test("PUT request with AAC content type")
    func putWithAAC() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.aac", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .aac, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("Content-Type: audio/aac\r\n"))
    }

    @Test("PUT request with Ogg Vorbis content type")
    func putWithOggVorbis() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.ogg", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .oggVorbis, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("Content-Type: application/ogg\r\n"))
    }

    @Test("PUT request with Ogg Opus content type")
    func putWithOggOpus() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.opus", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .oggOpus, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("Content-Type: audio/ogg\r\n"))
    }

    // MARK: - Edge Cases

    @Test("PUT request with Unicode station name")
    func putWithUnicodeName() {
        let unicodeStation = StationInfo(name: "Radio francaise", isPublic: true)
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: unicodeStation
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("ice-name: Radio francaise"))
    }

    @Test("SOURCE request with Authorization header")
    func sourceAuthorizationHeader() {
        let data = builder.buildIcecastSOURCE(
            mountpoint: "/live.mp3", credentials: credentials,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(request.contains("Authorization: Basic"))
    }

    @Test("PUT request has no User-Agent duplicate")
    func putNoUserAgentDuplicate() {
        let data = builder.buildIcecastPUT(
            mountpoint: "/live.mp3", credentials: credentials,
            host: "localhost", port: 8000,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        let count = request.components(separatedBy: "User-Agent:").count - 1
        #expect(count == 1)
    }

    @Test("SOURCE request has no Host header")
    func sourceNoHostHeader() {
        let data = builder.buildIcecastSOURCE(
            mountpoint: "/live.mp3", credentials: credentials,
            contentType: .mp3, stationInfo: station
        )
        let request = String(decoding: data, as: UTF8.self)
        #expect(!request.contains("Host:"))
    }
}
