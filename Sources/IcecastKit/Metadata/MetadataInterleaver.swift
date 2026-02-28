// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Interleaves ICY metadata blocks into an audio data stream at fixed byte intervals.
///
/// The interleaver maintains an internal byte counter. Every `metaint` bytes of audio,
/// it inserts a metadata block (either the current metadata or an empty block).
///
/// Stream structure:
/// ```
/// [audio: metaint bytes] [metadata block] [audio: metaint bytes] [metadata block] ...
/// ```
public actor MetadataInterleaver {

    /// The metadata interval in bytes (typically 8192).
    public let metaint: Int

    /// The metadata currently queued for insertion at the next interval.
    public private(set) var currentMetadata: ICYMetadata?

    private var byteCounter: Int = 0
    private let encoder = ICYMetadataEncoder()

    /// Creates a new metadata interleaver.
    ///
    /// - Parameter metaint: The metadata interval in bytes. Defaults to `8192`.
    public init(metaint: Int = 8192) {
        self.metaint = metaint
    }

    /// Updates the metadata to be inserted at the next interval boundary.
    ///
    /// Pass `nil` to clear (will insert empty metadata blocks).
    ///
    /// - Parameter metadata: The metadata to insert, or `nil` for empty blocks.
    public func updateMetadata(_ metadata: ICYMetadata?) {
        currentMetadata = metadata
    }

    /// Processes audio data, inserting metadata blocks at `metaint` boundaries.
    ///
    /// Takes raw audio data and returns the interleaved output containing
    /// audio chunks and metadata blocks at the correct positions.
    ///
    /// The interleaver tracks its position across multiple calls —
    /// you can feed audio data in any chunk size.
    ///
    /// - Parameter audioData: The raw audio data to process.
    /// - Returns: The interleaved output with metadata blocks inserted.
    /// - Throws: ``IcecastError/metadataTooLong(length:maxLength:)`` if the
    ///   current metadata exceeds the maximum size.
    public func interleave(_ audioData: Data) throws -> Data {
        guard !audioData.isEmpty else {
            return Data()
        }

        var output = Data()
        var offset = audioData.startIndex

        while offset < audioData.endIndex {
            let remaining = metaint - byteCounter
            let available = audioData.endIndex - offset
            let chunkSize = min(remaining, available)

            let chunkEnd = audioData.index(offset, offsetBy: chunkSize)
            output.append(audioData[offset..<chunkEnd])
            byteCounter += chunkSize
            offset = chunkEnd

            if byteCounter >= metaint {
                let metadataBlock = try encodeCurrentMetadata()
                output.append(metadataBlock)
                byteCounter = 0
            }
        }

        return output
    }

    /// Resets the byte counter and clears current metadata.
    public func reset() {
        byteCounter = 0
        currentMetadata = nil
    }

    // MARK: - Private

    /// Encodes the current metadata or returns an empty block.
    private func encodeCurrentMetadata() throws -> Data {
        if let metadata = currentMetadata {
            return try encoder.encode(metadata)
        }
        return encoder.encodeEmpty()
    }
}
