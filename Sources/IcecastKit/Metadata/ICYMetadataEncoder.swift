// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Encodes ``ICYMetadata`` into the binary wire format for inline stream metadata.
///
/// The ICY metadata protocol inserts metadata blocks at fixed byte intervals
/// within the audio stream. Each block starts with a length byte N, followed
/// by N x 16 bytes of zero-padded metadata string.
public struct ICYMetadataEncoder: Sendable {

    /// Maximum metadata payload size in bytes (255 x 16).
    static let maxPayloadSize = 255 * 16

    /// Creates a new ICY metadata encoder.
    public init() {}

    /// Encodes metadata into the binary wire format.
    ///
    /// Wire format:
    /// - Byte 0: N (length indicator, unsigned). Actual metadata length = N x 16.
    /// - Bytes 1...: metadata string zero-padded to N x 16 bytes.
    ///
    /// - Parameter metadata: The metadata to encode.
    /// - Returns: The binary-encoded metadata block.
    /// - Throws: ``IcecastError/metadataTooLong(length:maxLength:)`` if the
    ///   encoded string exceeds 4080 bytes.
    public func encode(_ metadata: ICYMetadata) throws -> Data {
        let metadataString = encodeString(metadata)
        let utf8Bytes = Data(metadataString.utf8)

        if utf8Bytes.isEmpty {
            return encodeEmpty()
        }

        let byteLength = utf8Bytes.count
        guard byteLength <= Self.maxPayloadSize else {
            throw IcecastError.metadataTooLong(
                length: byteLength,
                maxLength: Self.maxPayloadSize
            )
        }

        let n = (byteLength + 15) / 16
        let paddedLength = n * 16

        var output = Data(capacity: 1 + paddedLength)
        output.append(UInt8(n))
        output.append(utf8Bytes)

        let paddingCount = paddedLength - byteLength
        if paddingCount > 0 {
            output.append(contentsOf: [UInt8](repeating: 0, count: paddingCount))
        }

        return output
    }

    /// Encodes an empty metadata block (single zero byte, N=0).
    ///
    /// - Returns: A single-byte `Data` containing `0x00`.
    public func encodeEmpty() -> Data {
        Data([0x00])
    }

    /// Builds the metadata string representation without binary framing.
    ///
    /// Format: `StreamTitle='value';StreamUrl='value';CustomKey='value';`
    ///
    /// Field ordering: `StreamTitle` first, `StreamUrl` second,
    /// then custom fields in alphabetical order.
    ///
    /// - Parameter metadata: The metadata to encode as a string.
    /// - Returns: The formatted metadata string.
    public func encodeString(_ metadata: ICYMetadata) -> String {
        var parts: [String] = []

        if let title = metadata.streamTitle {
            parts.append("StreamTitle='\(escapeValue(title))';")
        }
        if let url = metadata.streamUrl {
            parts.append("StreamUrl='\(escapeValue(url))';")
        }

        for key in metadata.customFields.keys.sorted() {
            if let value = metadata.customFields[key] {
                parts.append("\(key)='\(escapeValue(value))';")
            }
        }

        return parts.joined()
    }

    // MARK: - Private

    /// Escapes single quotes in a metadata value using backslash.
    private func escapeValue(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "\\'")
    }
}
