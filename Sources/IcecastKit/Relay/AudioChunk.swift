// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// A chunk of audio data received from an Icecast stream.
///
/// Audio chunks are emitted by ``IcecastRelay/audioStream`` and contain
/// raw audio bytes along with any ICY metadata present at that point
/// in the stream.
public struct AudioChunk: Sendable {
    /// Raw audio bytes (MP3 frames, AAC ADTS frames, Ogg pages, etc.).
    public let data: Data

    /// ICY metadata present at this point in the stream, if any.
    public let metadata: ICYMetadata?

    /// Audio content type detected from HTTP response headers.
    public let contentType: AudioContentType

    /// Reception timestamp.
    public let timestamp: Date

    /// Total bytes received including this chunk (cumulative offset).
    public let byteOffset: Int64

    /// Creates an audio chunk.
    ///
    /// - Parameters:
    ///   - data: Raw audio bytes.
    ///   - metadata: ICY metadata present at this point, if any.
    ///   - contentType: Audio content type from HTTP headers.
    ///   - timestamp: Reception timestamp.
    ///   - byteOffset: Cumulative byte offset including this chunk.
    public init(
        data: Data,
        metadata: ICYMetadata? = nil,
        contentType: AudioContentType,
        timestamp: Date = Date(),
        byteOffset: Int64
    ) {
        self.data = data
        self.metadata = metadata
        self.contentType = contentType
        self.timestamp = timestamp
        self.byteOffset = byteOffset
    }
}
