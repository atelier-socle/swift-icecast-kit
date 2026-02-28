// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

extension Data {

    /// The CRLF byte sequence used in HTTP protocol.
    static let crlf = Data([0x0D, 0x0A])

    /// The double CRLF byte sequence marking the end of HTTP headers.
    static let doubleCRLF = Data([0x0D, 0x0A, 0x0D, 0x0A])

    /// Finds the first occurrence of the CRLF sequence in the data.
    ///
    /// - Returns: The range of the first CRLF, or `nil` if not found.
    func findCRLF() -> Range<Data.Index>? {
        range(of: Data.crlf)
    }

    /// Finds the first occurrence of the double CRLF sequence in the data.
    ///
    /// - Returns: The range of the first double CRLF, or `nil` if not found.
    func findDoubleCRLF() -> Range<Data.Index>? {
        range(of: Data.doubleCRLF)
    }

    /// Extracts a subrange of data as a new `Data` instance.
    ///
    /// - Parameter range: The range to extract.
    /// - Returns: A new `Data` containing the bytes in the given range.
    func subrange(_ range: Range<Data.Index>) -> Data {
        subdata(in: range)
    }

    /// Converts the data to a UTF-8 string, returning `nil` if the data
    /// contains invalid UTF-8 sequences.
    ///
    /// - Returns: A UTF-8 string, or `nil` if conversion fails.
    func toUTF8String() -> String? {
        String(data: self, encoding: .utf8)
    }

    /// Converts the data to a UTF-8 string, replacing invalid sequences
    /// with the Unicode replacement character.
    ///
    /// - Returns: A UTF-8 string with lossy replacement for invalid bytes.
    func toUTF8StringLossy() -> String {
        String(decoding: self, as: UTF8.self)
    }

    /// Splits the data at each CRLF boundary into an array of `Data` segments.
    ///
    /// - Returns: An array of `Data` segments between CRLF boundaries.
    func splitByCRLF() -> [Data] {
        var results: [Data] = []
        var searchRange = startIndex..<endIndex

        while searchRange.lowerBound < searchRange.upperBound {
            if let crlfRange = self[searchRange].range(of: Data.crlf) {
                let lineRange = searchRange.lowerBound..<crlfRange.lowerBound
                results.append(subdata(in: lineRange))
                searchRange = crlfRange.upperBound..<endIndex
            } else {
                results.append(subdata(in: searchRange))
                break
            }
        }

        return results
    }
}
