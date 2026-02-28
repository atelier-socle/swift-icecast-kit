// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("String+ICY Extensions")
struct StringICYTests {

    @Test("icyURLEncoded encodes spaces")
    func urlEncodedSpaces() {
        let encoded = "hello world".icyURLEncoded()
        #expect(encoded == "hello%20world")
    }

    @Test("icyURLEncoded preserves safe characters")
    func urlEncodedSafe() {
        let encoded = "hello-world_123".icyURLEncoded()
        #expect(encoded == "hello-world_123")
    }

    @Test("icySingleQuoteEscaped doubles single quotes")
    func singleQuoteEscaped() {
        let escaped = "It's a test".icySingleQuoteEscaped()
        #expect(escaped == "It''s a test")
    }

    @Test("icySingleQuoteEscaped with no quotes returns same string")
    func singleQuoteNoChange() {
        let escaped = "No quotes here".icySingleQuoteEscaped()
        #expect(escaped == "No quotes here")
    }

    @Test("base64Encoded encodes correctly")
    func base64Encoded() {
        let encoded = "source:hackme".base64Encoded()
        #expect(encoded == "c291cmNlOmhhY2ttZQ==")
    }

    @Test("base64Encoded handles empty string")
    func base64EncodedEmpty() {
        let encoded = "".base64Encoded()
        #expect(encoded == "")
    }

    @Test("toUTF8Data converts string to data")
    func toUTF8Data() {
        let data = "Hello".toUTF8Data()
        #expect(data == Data("Hello".utf8))
    }

    @Test("toUTF8Data handles empty string")
    func toUTF8DataEmpty() {
        let data = "".toUTF8Data()
        #expect(data == Data())
    }

    @Test("icyPathEncoded encodes path characters")
    func pathEncoded() {
        let encoded = "/live stream.mp3".icyPathEncoded()
        #expect(encoded.contains("/"))
        #expect(encoded.contains("%20"))
    }

    @Test("icyURLEncoded handles Unicode characters")
    func urlEncodedUnicode() {
        let encoded = "Radio francaise".icyURLEncoded()
        #expect(!encoded.isEmpty)
    }

    @Test("icySingleQuoteEscaped handles multiple quotes")
    func singleQuoteMultiple() {
        let escaped = "it's it's it's".icySingleQuoteEscaped()
        #expect(escaped == "it''s it''s it''s")
    }
}
