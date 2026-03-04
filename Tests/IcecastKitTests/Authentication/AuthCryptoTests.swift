// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("AuthCrypto — MD5")
struct AuthCryptoMD5Tests {

    @Test("MD5 of empty string matches known hash")
    func md5EmptyString() {
        let result = AuthCrypto.md5("")
        #expect(result == "d41d8cd98f00b204e9800998ecf8427e")
    }

    @Test("MD5 of 'abc' matches known hash")
    func md5Abc() {
        let result = AuthCrypto.md5("abc")
        #expect(result == "900150983cd24fb0d6963f7d28e17f72")
    }

    @Test("MD5 of 'message digest' matches known hash")
    func md5MessageDigest() {
        let result = AuthCrypto.md5("message digest")
        #expect(result == "f96b697d7cb7938d525a2f31aaf161d0")
    }

    @Test("MD5 produces 32-character lowercase hex string")
    func md5FormatCorrect() {
        let result = AuthCrypto.md5("test")
        #expect(result.count == 32)
        #expect(result == result.lowercased())
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(result.unicodeScalars.allSatisfy { hexChars.contains($0) })
    }
}

@Suite("AuthCrypto — SHA-256")
struct AuthCryptoSHA256Tests {

    @Test("SHA-256 of empty string matches known hash")
    func sha256EmptyString() {
        let result = AuthCrypto.sha256("")
        #expect(
            result
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    @Test("SHA-256 of 'abc' matches known hash")
    func sha256Abc() {
        let result = AuthCrypto.sha256("abc")
        #expect(
            result
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("SHA-256 produces 64-character lowercase hex string")
    func sha256FormatCorrect() {
        let result = AuthCrypto.sha256("test")
        #expect(result.count == 64)
        #expect(result == result.lowercased())
    }

    @Test("SHA-256 of unicode string produces valid hash")
    func sha256Unicode() {
        let result = AuthCrypto.sha256("hé™llo🌍")
        #expect(result.count == 64)
    }

    @Test("SHA-256 of long string produces valid hash")
    func sha256LongString() {
        let longString = String(repeating: "a", count: 10000)
        let result = AuthCrypto.sha256(longString)
        #expect(result.count == 64)
    }
}
