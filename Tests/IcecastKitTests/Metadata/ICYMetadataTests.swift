// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("ICYMetadata")
struct ICYMetadataTests {

    // MARK: - isEmpty

    @Test("All nil fields → isEmpty is true")
    func emptyMetadata() {
        let metadata = ICYMetadata()
        #expect(metadata.isEmpty)
    }

    @Test("streamTitle set → isEmpty is false")
    func notEmptyWithTitle() {
        let metadata = ICYMetadata(streamTitle: "Artist - Song")
        #expect(!metadata.isEmpty)
    }

    @Test("streamUrl set → isEmpty is false")
    func notEmptyWithUrl() {
        let metadata = ICYMetadata(streamUrl: "http://example.com")
        #expect(!metadata.isEmpty)
    }

    @Test("Only customFields → isEmpty is false")
    func notEmptyWithCustomFields() {
        let metadata = ICYMetadata(customFields: ["key": "value"])
        #expect(!metadata.isEmpty)
    }

    @Test("Empty string streamTitle → isEmpty is false")
    func notEmptyWithEmptyTitle() {
        let metadata = ICYMetadata(streamTitle: "")
        #expect(!metadata.isEmpty)
    }

    // MARK: - urlEncodedSong

    @Test("Simple title encoded correctly")
    func urlEncodedSimple() {
        let metadata = ICYMetadata(streamTitle: "Artist - Song")
        #expect(metadata.urlEncodedSong() == "Artist+-+Song")
    }

    @Test("Special characters are percent-encoded")
    func urlEncodedSpecialChars() {
        let metadata = ICYMetadata(streamTitle: "A&B=C")
        let encoded = metadata.urlEncodedSong()
        #expect(encoded?.contains("%26") == true)
        #expect(encoded?.contains("%3D") == true)
    }

    @Test("Nil streamTitle → nil result")
    func urlEncodedNilTitle() {
        let metadata = ICYMetadata()
        #expect(metadata.urlEncodedSong() == nil)
    }

    @Test("Unicode characters are percent-encoded")
    func urlEncodedUnicode() {
        let metadata = ICYMetadata(streamTitle: "Cafe\u{0301}")
        let encoded = metadata.urlEncodedSong()
        #expect(encoded != nil)
        #expect(encoded != "Cafe\u{0301}")
    }

    @Test("Plus signs are percent-encoded")
    func urlEncodedPlusSign() {
        let metadata = ICYMetadata(streamTitle: "A+B")
        let encoded = metadata.urlEncodedSong()
        #expect(encoded == "A%2BB")
    }

    // MARK: - Codable

    @Test("Codable roundtrip with all fields")
    func codableRoundtrip() throws {
        let metadata = ICYMetadata(
            streamTitle: "Artist - Song",
            streamUrl: "http://example.com",
            customFields: ["key": "value"]
        )
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(ICYMetadata.self, from: data)
        #expect(decoded == metadata)
    }

    @Test("Codable roundtrip with nil fields")
    func codableRoundtripNil() throws {
        let metadata = ICYMetadata()
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(ICYMetadata.self, from: data)
        #expect(decoded == metadata)
    }

    // MARK: - Hashable / Equatable

    @Test("Same fields → equal")
    func equatableSame() {
        let a = ICYMetadata(streamTitle: "Song")
        let b = ICYMetadata(streamTitle: "Song")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Different fields → not equal")
    func equatableDifferent() {
        let a = ICYMetadata(streamTitle: "Song A")
        let b = ICYMetadata(streamTitle: "Song B")
        #expect(a != b)
    }

    @Test("Different customFields → not equal")
    func equatableDifferentCustom() {
        let a = ICYMetadata(customFields: ["k": "v1"])
        let b = ICYMetadata(customFields: ["k": "v2"])
        #expect(a != b)
    }
}
