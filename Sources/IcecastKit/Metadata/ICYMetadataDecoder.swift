// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Decodes ICY metadata from the binary wire format.
///
/// Parses the length-prefixed metadata blocks embedded in audio streams
/// back into ``ICYMetadata`` values.
public struct ICYMetadataDecoder: Sendable {

    /// Creates a new ICY metadata decoder.
    public init() {}

    /// Decodes a binary metadata block starting from byte 0.
    ///
    /// Returns the decoded metadata and total bytes consumed (1 + N x 16).
    /// If the first byte is 0 (N=0), returns empty metadata and `bytesConsumed=1`.
    ///
    /// - Parameter data: The raw data starting with the length byte.
    /// - Returns: A tuple of the decoded metadata and the number of bytes consumed.
    /// - Throws: ``IcecastError/metadataEncodingFailed(reason:)`` if the data
    ///   is too short for the declared length.
    public func decode(from data: Data) throws -> (metadata: ICYMetadata, bytesConsumed: Int) {
        guard !data.isEmpty else {
            throw IcecastError.metadataEncodingFailed(reason: "Empty metadata block")
        }

        let n = Int(data[data.startIndex])

        if n == 0 {
            return (ICYMetadata(), 1)
        }

        let payloadLength = n * 16
        let totalLength = 1 + payloadLength

        guard data.count >= totalLength else {
            throw IcecastError.metadataEncodingFailed(
                reason: "Data too short: need \(totalLength) bytes, have \(data.count)"
            )
        }

        let payloadRange =
            data.index(
                data.startIndex, offsetBy: 1)..<data.index(
                data.startIndex, offsetBy: totalLength)
        var payload = data.subdata(in: payloadRange)

        // Strip trailing zero bytes
        while let last = payload.last, last == 0 {
            payload = payload.dropLast()
        }

        let metadataString = String(decoding: payload, as: UTF8.self)
        let metadata = parse(string: metadataString)

        return (metadata, totalLength)
    }

    /// Parses a metadata string (without binary framing) into ``ICYMetadata``.
    ///
    /// Input format: `StreamTitle='value';StreamUrl='value';`
    ///
    /// Handles escaped single quotes (`\'`) inside values.
    /// Unrecognized keys are stored in ``ICYMetadata/customFields``.
    ///
    /// - Parameter string: The metadata string to parse.
    /// - Returns: The parsed metadata.
    public func parse(string: String) -> ICYMetadata {
        var streamTitle: String?
        var streamUrl: String?
        var customFields: [String: String] = [:]

        let pairs = extractPairs(from: string)

        for (key, value) in pairs {
            let unescaped = value.replacingOccurrences(of: "\\'", with: "'")
            switch key {
            case "StreamTitle":
                streamTitle = unescaped
            case "StreamUrl":
                streamUrl = unescaped
            default:
                customFields[key] = unescaped
            }
        }

        return ICYMetadata(
            streamTitle: streamTitle,
            streamUrl: streamUrl,
            customFields: customFields
        )
    }

    // MARK: - Private

    /// Extracts key-value pairs from an ICY metadata string.
    ///
    /// Handles escaped single quotes (`\'`) inside values.
    private func extractPairs(from string: String) -> [(String, String)] {
        var pairs: [(String, String)] = []
        var index = string.startIndex

        while index < string.endIndex {
            guard let equalsIndex = string[index...].firstIndex(of: "=") else {
                break
            }

            let key = String(string[index..<equalsIndex])
            var valueStart = string.index(after: equalsIndex)
            guard valueStart < string.endIndex else { break }

            guard string[valueStart] == "'" else {
                index = skipToNextPair(in: string, from: valueStart)
                continue
            }

            valueStart = string.index(after: valueStart)
            let (value, endIndex) = extractQuotedValue(from: string, startingAt: valueStart)

            if !key.isEmpty {
                pairs.append((key, value))
            }

            index = advancePastTerminator(in: string, from: endIndex)
        }

        return pairs
    }

    /// Extracts a quoted value, handling backslash-escaped single quotes.
    private func extractQuotedValue(
        from string: String,
        startingAt start: String.Index
    ) -> (String, String.Index) {
        var position = start
        var value = ""

        while position < string.endIndex {
            let char = string[position]
            if char == "\\", string.index(after: position) < string.endIndex,
                string[string.index(after: position)] == "'"
            {
                value.append("\\'")
                position = string.index(position, offsetBy: 2)
                continue
            }
            if char == "'" {
                break
            }
            value.append(char)
            position = string.index(after: position)
        }

        return (value, position)
    }

    /// Skips to the next pair by finding the next semicolon.
    private func skipToNextPair(in string: String, from index: String.Index) -> String.Index {
        if let semicolonIndex = string[index...].firstIndex(of: ";") {
            return string.index(after: semicolonIndex)
        }
        return string.endIndex
    }

    /// Advances past the closing quote and optional semicolon.
    private func advancePastTerminator(in string: String, from index: String.Index) -> String.Index {
        var position = index
        if position < string.endIndex {
            position = string.index(after: position)
        }
        if position < string.endIndex, string[position] == ";" {
            position = string.index(after: position)
        }
        return position
    }
}
