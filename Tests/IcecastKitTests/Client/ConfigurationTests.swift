// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Configuration and Credentials")
struct ConfigurationTests {

    // MARK: - IcecastCredentials

    @Test("Default username is 'source'")
    func defaultUsername() {
        let creds = IcecastCredentials(password: "hackme")
        #expect(creds.username == "source")
    }

    @Test("Custom username is preserved")
    func customUsername() {
        let creds = IcecastCredentials(username: "admin", password: "secret")
        #expect(creds.username == "admin")
        #expect(creds.password == "secret")
    }

    @Test("Basic auth header encoding is correct")
    func basicAuthEncoding() {
        let creds = IcecastCredentials(username: "source", password: "hackme")
        let header = creds.basicAuthHeaderValue()
        let expectedBase64 = Data("source:hackme".utf8).base64EncodedString()
        #expect(header == "Basic \(expectedBase64)")
    }

    @Test("Shoutcast convenience initializer sets empty username")
    func shoutcastConvenience() {
        let creds = IcecastCredentials.shoutcast(password: "mypass")
        #expect(creds.username == "")
        #expect(creds.password == "mypass")
    }

    @Test("ShoutcastV2 convenience initializer encodes stream ID")
    func shoutcastV2Convenience() {
        let creds = IcecastCredentials.shoutcastV2(password: "mypass", streamId: 1)
        #expect(creds.username == "sid=1")
        #expect(creds.password == "mypass")
    }

    @Test("Credentials are Hashable")
    func credentialsHashable() {
        let c1 = IcecastCredentials(password: "a")
        let c2 = IcecastCredentials(password: "a")
        #expect(c1 == c2)
        #expect(c1.hashValue == c2.hashValue)
    }

    // MARK: - AudioContentType

    @Test("MP3 raw value is audio/mpeg")
    func mp3RawValue() {
        #expect(AudioContentType.mp3.rawValue == "audio/mpeg")
    }

    @Test("AAC raw value is audio/aac")
    func aacRawValue() {
        #expect(AudioContentType.aac.rawValue == "audio/aac")
    }

    @Test("Ogg Vorbis raw value is application/ogg")
    func oggVorbisRawValue() {
        #expect(AudioContentType.oggVorbis.rawValue == "application/ogg")
    }

    @Test("Ogg Opus raw value is audio/ogg")
    func oggOpusRawValue() {
        #expect(AudioContentType.oggOpus.rawValue == "audio/ogg")
    }

    @Test("Detect MP3 from filename")
    func detectMP3() {
        #expect(AudioContentType.detect(from: "song.mp3") == .mp3)
        #expect(AudioContentType.detect(from: "SONG.MP3") == .mp3)
    }

    @Test("Detect AAC from filename")
    func detectAAC() {
        #expect(AudioContentType.detect(from: "song.aac") == .aac)
        #expect(AudioContentType.detect(from: "song.m4a") == .aac)
    }

    @Test("Detect Ogg from filename")
    func detectOgg() {
        #expect(AudioContentType.detect(from: "song.ogg") == .oggVorbis)
        #expect(AudioContentType.detect(from: "song.oga") == .oggVorbis)
    }

    @Test("Detect Opus from filename")
    func detectOpus() {
        #expect(AudioContentType.detect(from: "song.opus") == .oggOpus)
    }

    @Test("Detect unknown extension returns nil")
    func detectUnknown() {
        #expect(AudioContentType.detect(from: "song.wav") == nil)
        #expect(AudioContentType.detect(from: "song.flac") == nil)
        #expect(AudioContentType.detect(from: "noextension") == nil)
    }

    // MARK: - StationInfo

    @Test("audioInfoHeaderValue with all fields")
    func audioInfoAllFields() {
        let info = StationInfo(bitrate: 128, sampleRate: 44100, channels: 2)
        let value = info.audioInfoHeaderValue()
        #expect(value == "ice-channels=2;ice-samplerate=44100;ice-bitrate=128")
    }

    @Test("audioInfoHeaderValue with partial fields")
    func audioInfoPartialFields() {
        let info = StationInfo(bitrate: 128)
        let value = info.audioInfoHeaderValue()
        #expect(value == "ice-bitrate=128")
    }

    @Test("audioInfoHeaderValue returns nil when empty")
    func audioInfoNilWhenEmpty() {
        let info = StationInfo()
        let value = info.audioInfoHeaderValue()
        #expect(value == nil)
    }

    @Test("StationInfo default isPublic is false")
    func stationInfoDefaultPublic() {
        let info = StationInfo()
        #expect(!info.isPublic)
    }

    // MARK: - ProtocolMode

    @Test("ProtocolMode cases are Hashable")
    func protocolModeHashable() {
        let m1 = ProtocolMode.auto
        let m2 = ProtocolMode.auto
        #expect(m1 == m2)
    }

    @Test("ProtocolMode different cases are not equal")
    func protocolModeDifferent() {
        #expect(ProtocolMode.icecastPUT != ProtocolMode.icecastSOURCE)
    }

    @Test("ProtocolMode shoutcastV2 with different stream IDs are not equal")
    func protocolModeShoutcastV2Different() {
        #expect(ProtocolMode.shoutcastV2(streamId: 1) != ProtocolMode.shoutcastV2(streamId: 2))
    }

    @Test("ProtocolMode shoutcastV2 with same stream ID are equal")
    func protocolModeShoutcastV2Same() {
        #expect(ProtocolMode.shoutcastV2(streamId: 1) == ProtocolMode.shoutcastV2(streamId: 1))
    }

    // MARK: - ProtocolMode Codable

    @Test("ProtocolMode auto Codable roundtrip")
    func protocolModeAutoRoundtrip() throws {
        let mode = ProtocolMode.auto
        let data = try JSONEncoder().encode(mode)
        let decoded = try JSONDecoder().decode(ProtocolMode.self, from: data)
        #expect(decoded == mode)
    }

    @Test("ProtocolMode shoutcastV2 Codable roundtrip")
    func protocolModeShoutcastV2Roundtrip() throws {
        let mode = ProtocolMode.shoutcastV2(streamId: 3)
        let data = try JSONEncoder().encode(mode)
        let decoded = try JSONDecoder().decode(ProtocolMode.self, from: data)
        #expect(decoded == mode)
    }

    @Test("ProtocolMode all cases Codable roundtrip")
    func protocolModeAllCasesRoundtrip() throws {
        let modes: [ProtocolMode] = [.auto, .icecastPUT, .icecastSOURCE, .shoutcastV1, .shoutcastV2(streamId: 5)]
        for mode in modes {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(ProtocolMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    // MARK: - AudioContentType CaseIterable

    @Test("AudioContentType has 4 cases via CaseIterable")
    func audioContentTypeCaseIterable() {
        #expect(AudioContentType.allCases.count == 4)
        #expect(AudioContentType.allCases.contains(.mp3))
        #expect(AudioContentType.allCases.contains(.aac))
        #expect(AudioContentType.allCases.contains(.oggVorbis))
        #expect(AudioContentType.allCases.contains(.oggOpus))
    }

    @Test("AudioContentType detect is case-insensitive")
    func audioContentTypeDetectCaseInsensitive() {
        #expect(AudioContentType.detect(from: "SONG.MP3") == .mp3)
        #expect(AudioContentType.detect(from: "Song.Ogg") == .oggVorbis)
        #expect(AudioContentType.detect(from: "TRACK.OPUS") == .oggOpus)
        #expect(AudioContentType.detect(from: "file.AAC") == .aac)
    }

    // MARK: - StationInfo Codable

    @Test("StationInfo Codable roundtrip")
    func stationInfoCodableRoundtrip() throws {
        let info = StationInfo(
            name: "Test Radio",
            description: "The best",
            url: "https://test.com",
            genre: "Rock;Pop",
            isPublic: true,
            bitrate: 128,
            sampleRate: 44100,
            channels: 2
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(StationInfo.self, from: data)
        #expect(decoded == info)
    }

    // MARK: - IcecastCredentials Codable

    @Test("IcecastCredentials Codable roundtrip")
    func credentialsCodableRoundtrip() throws {
        let creds = IcecastCredentials(username: "source", password: "hackme")
        let data = try JSONEncoder().encode(creds)
        let decoded = try JSONDecoder().decode(IcecastCredentials.self, from: data)
        #expect(decoded == creds)
    }

    @Test("IcecastCredentials shoutcastV2 has correct username format")
    func credentialsShoutcastV2Format() {
        let creds = IcecastCredentials.shoutcastV2(password: "hackme", streamId: 2)
        #expect(creds.username == "sid=2")
        #expect(creds.password == "hackme")
    }
}
