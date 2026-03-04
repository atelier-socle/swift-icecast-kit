// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Demultiplexes raw ICY stream bytes into audio data and ICY metadata.
///
/// When Icecast or SHOUTcast servers send metadata interleaved with audio,
/// they use the ICY metadata protocol: every `metaint` audio bytes, a metadata
/// block is inserted. This struct separates those two streams.
///
/// The ICY metadata protocol works as follows:
/// 1. Server sends `icy-metaint: N` in HTTP response headers
/// 2. After every `N` bytes of audio, a metadata block is inserted
/// 3. The first byte of the block is `length / 16` (0 = no metadata)
/// 4. Followed by `length * 16` bytes of metadata content
/// 5. Then the next `N` bytes of audio resume
struct ICYStreamDemuxer: Sendable {

    /// Result of demultiplexing a chunk of raw stream data.
    struct DemuxResult: Sendable {
        /// Pure audio bytes extracted (ICY metadata blocks removed).
        let audioBytes: Data
        /// Metadata encountered in this chunk, if any.
        let metadata: ICYMetadata?
    }

    private let metaint: Int?
    private var bytesUntilMetadata: Int
    private var metadataBuffer: Data
    private var expectedMetadataLength: Int?
    private let decoder: ICYMetadataDecoder

    /// Creates a demuxer with the metaint value from the server's `icy-metaint` header.
    ///
    /// Pass `nil` if the server did not send `icy-metaint` (no metadata interleaving).
    ///
    /// - Parameter metaint: The number of audio bytes between metadata blocks.
    init(metaint: Int?) {
        self.metaint = metaint
        self.bytesUntilMetadata = metaint ?? 0
        self.metadataBuffer = Data()
        self.expectedMetadataLength = nil
        self.decoder = ICYMetadataDecoder()
    }

    /// Feed raw bytes from the network. Returns demultiplexed audio bytes
    /// and any metadata block encountered, in order.
    ///
    /// - Parameter bytes: Raw bytes received from the network.
    /// - Returns: The demultiplexed result with audio bytes and optional metadata.
    mutating func feed(_ bytes: Data) -> DemuxResult {
        guard let metaint, metaint > 0 else {
            return DemuxResult(audioBytes: bytes, metadata: nil)
        }

        var audioOutput = Data()
        var latestMetadata: ICYMetadata?
        var offset = bytes.startIndex

        while offset < bytes.endIndex {
            if let expectedLength = expectedMetadataLength {
                let remaining = expectedLength - metadataBuffer.count
                let available = bytes.endIndex - offset
                let toRead = min(remaining, available)

                metadataBuffer.append(bytes[offset..<(offset + toRead)])
                offset += toRead

                if metadataBuffer.count == expectedLength {
                    let parsed = parseMetadataBlock(metadataBuffer)
                    if let parsed, !parsed.isEmpty {
                        latestMetadata = parsed
                    }
                    metadataBuffer = Data()
                    expectedMetadataLength = nil
                    bytesUntilMetadata = metaint
                }
            } else if bytesUntilMetadata == 0 {
                let lengthByte = Int(bytes[offset])
                offset += 1
                let payloadLength = lengthByte * 16

                if payloadLength == 0 {
                    bytesUntilMetadata = metaint
                } else {
                    expectedMetadataLength = payloadLength
                    metadataBuffer = Data()
                }
            } else {
                let available = bytes.endIndex - offset
                let toRead = min(bytesUntilMetadata, available)

                audioOutput.append(bytes[offset..<(offset + toRead)])
                offset += toRead
                bytesUntilMetadata -= toRead
            }
        }

        return DemuxResult(audioBytes: audioOutput, metadata: latestMetadata)
    }

    /// Parses a metadata block using the existing ICY decoder.
    private func parseMetadataBlock(_ data: Data) -> ICYMetadata? {
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .controlCharacters)
            .trimmingCharacters(in: .init(charactersIn: "\0"))

        guard !text.isEmpty else { return nil }

        return decoder.parse(string: text)
    }
}
