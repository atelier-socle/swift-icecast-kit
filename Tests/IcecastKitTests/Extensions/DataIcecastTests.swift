// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Data+Icecast Extensions")
struct DataIcecastTests {

    @Test("findCRLF finds CRLF in data")
    func findCRLF() {
        let data = Data("Hello\r\nWorld".utf8)
        let range = data.findCRLF()
        #expect(range != nil)
        #expect(range?.lowerBound == 5)
    }

    @Test("findCRLF returns nil when no CRLF")
    func findCRLFNil() {
        let data = Data("Hello World".utf8)
        let range = data.findCRLF()
        #expect(range == nil)
    }

    @Test("findDoubleCRLF finds double CRLF")
    func findDoubleCRLF() {
        let data = Data("Header\r\n\r\nBody".utf8)
        let range = data.findDoubleCRLF()
        #expect(range != nil)
    }

    @Test("findDoubleCRLF returns nil with single CRLF only")
    func findDoubleCRLFNil() {
        let data = Data("Hello\r\nWorld".utf8)
        let range = data.findDoubleCRLF()
        #expect(range == nil)
    }

    @Test("toUTF8String converts valid UTF-8")
    func toUTF8StringValid() {
        let data = Data("Hello, world!".utf8)
        #expect(data.toUTF8String() == "Hello, world!")
    }

    @Test("toUTF8String returns nil for invalid UTF-8")
    func toUTF8StringInvalid() {
        let data = Data([0xFF, 0xFE])
        #expect(data.toUTF8String() == nil)
    }

    @Test("toUTF8StringLossy handles invalid bytes")
    func toUTF8StringLossy() {
        let data = Data([0x48, 0x69, 0xFF])
        let result = data.toUTF8StringLossy()
        #expect(result.hasPrefix("Hi"))
    }

    @Test("splitByCRLF splits data correctly")
    func splitByCRLF() {
        let data = Data("line1\r\nline2\r\nline3".utf8)
        let parts = data.splitByCRLF()
        #expect(parts.count == 3)
        #expect(parts[0] == Data("line1".utf8))
        #expect(parts[1] == Data("line2".utf8))
        #expect(parts[2] == Data("line3".utf8))
    }

    @Test("splitByCRLF with empty data returns empty array")
    func splitByCRLFEmpty() {
        let data = Data()
        let parts = data.splitByCRLF()
        #expect(parts.isEmpty)
    }

    @Test("splitByCRLF with no CRLF returns single element")
    func splitByCRLFNoCRLF() {
        let data = Data("no line breaks".utf8)
        let parts = data.splitByCRLF()
        #expect(parts.count == 1)
        #expect(parts[0] == data)
    }

    @Test("subrange extracts correct bytes")
    func subrangeExtraction() {
        let data = Data("Hello, World!".utf8)
        let sub = data.subrange(0..<5)
        #expect(sub == Data("Hello".utf8))
    }

    @Test("CRLF static constant is correct")
    func crlfConstant() {
        #expect(Data.crlf == Data([0x0D, 0x0A]))
    }

    @Test("doubleCRLF static constant is correct")
    func doubleCRLFConstant() {
        #expect(Data.doubleCRLF == Data([0x0D, 0x0A, 0x0D, 0x0A]))
    }
}
