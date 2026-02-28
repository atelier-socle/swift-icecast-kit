// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit
@testable import IcecastKitCommands

@Suite("AudioFileReader")
struct AudioFileReaderTests {

    // MARK: - Content Type Detection

    @Test("Detect .mp3 extension")
    func detectMp3() {
        let result = AudioFileReader.detectContentType(from: "song.mp3")
        #expect(result == .mp3)
    }

    @Test("Detect .aac extension")
    func detectAac() {
        let result = AudioFileReader.detectContentType(from: "song.aac")
        #expect(result == .aac)
    }

    @Test("Detect .ogg extension")
    func detectOgg() {
        let result = AudioFileReader.detectContentType(from: "song.ogg")
        #expect(result == .oggVorbis)
    }

    @Test("Detect .opus extension")
    func detectOpus() {
        let result = AudioFileReader.detectContentType(from: "song.opus")
        #expect(result == .oggOpus)
    }

    @Test("Detect case-insensitive extensions")
    func detectCaseInsensitive() {
        #expect(AudioFileReader.detectContentType(from: "SONG.MP3") == .mp3)
        #expect(AudioFileReader.detectContentType(from: "song.Ogg") == .oggVorbis)
    }

    @Test("Unknown extension returns nil")
    func unknownExtensionReturnsNil() {
        let result = AudioFileReader.detectContentType(from: "file.wav")
        #expect(result == nil)
    }

    // MARK: - File Reading (with temp files)

    @Test("Override content type ignores extension")
    func overrideContentType() throws {
        let path = try createTempFile(ext: "mp3", bytes: 100)
        defer { removeTempFile(path) }
        let reader = try AudioFileReader(path: path, contentType: .aac)
        #expect(reader.contentType == .aac)
    }

    @Test("Read chunk returns data of requested size")
    func readChunkReturnsRequestedSize() throws {
        let path = try createTempFile(ext: "mp3", bytes: 1000)
        defer { removeTempFile(path) }
        var reader = try AudioFileReader(path: path)
        let chunk = try reader.readChunk(size: 100)
        #expect(chunk?.count == 100)
    }

    @Test("Read chunk at EOF returns nil")
    func readChunkAtEOFReturnsNil() throws {
        let path = try createTempFile(ext: "mp3", bytes: 10)
        defer { removeTempFile(path) }
        var reader = try AudioFileReader(path: path)
        _ = try reader.readChunk(size: 10)
        let eof = try reader.readChunk(size: 10)
        #expect(eof == nil)
    }

    @Test("isEOF false initially, true after all data read")
    func isEOFLifecycle() throws {
        let path = try createTempFile(ext: "mp3", bytes: 10)
        defer { removeTempFile(path) }
        var reader = try AudioFileReader(path: path)
        #expect(!reader.isEOF)
        _ = try reader.readChunk(size: 10)
        #expect(reader.isEOF)
    }

    @Test("Sequential reads cover entire file")
    func sequentialReads() throws {
        let path = try createTempFile(ext: "mp3", bytes: 100)
        defer { removeTempFile(path) }
        var reader = try AudioFileReader(path: path)
        var totalRead = 0
        while let chunk = try reader.readChunk(size: 30) {
            totalRead += chunk.count
        }
        #expect(totalRead == 100)
    }

    @Test("Reset returns to beginning")
    func resetReturnsToBeginning() throws {
        let path = try createTempFile(ext: "mp3", bytes: 50)
        defer { removeTempFile(path) }
        var reader = try AudioFileReader(path: path)
        _ = try reader.readChunk(size: 50)
        #expect(reader.isEOF)
        try reader.reset()
        #expect(!reader.isEOF)
    }

    @Test("Reset then read returns same first chunk")
    func resetThenReadReturnsSameData() throws {
        let path = try createTempFile(ext: "mp3", bytes: 50)
        defer { removeTempFile(path) }
        var reader = try AudioFileReader(path: path)
        let first = try reader.readChunk(size: 20)
        try reader.reset()
        let again = try reader.readChunk(size: 20)
        #expect(first == again)
    }

    @Test("File not found throws error")
    func fileNotFoundThrows() {
        #expect(throws: AudioFileError.self) {
            _ = try AudioFileReader(path: "/nonexistent/file.mp3")
        }
    }

    @Test("Empty file first readChunk returns nil")
    func emptyFileReturnsNil() throws {
        let path = try createTempFile(ext: "mp3", bytes: 0)
        defer { removeTempFile(path) }
        var reader = try AudioFileReader(path: path)
        let chunk = try reader.readChunk()
        #expect(chunk == nil)
    }

    @Test("Default chunk size is 4096")
    func defaultChunkSize() throws {
        let path = try createTempFile(ext: "mp3", bytes: 8192)
        defer { removeTempFile(path) }
        var reader = try AudioFileReader(path: path)
        let chunk = try reader.readChunk()
        #expect(chunk?.count == 4096)
    }

    @Test("Custom chunk size")
    func customChunkSize() throws {
        let path = try createTempFile(ext: "mp3", bytes: 500)
        defer { removeTempFile(path) }
        var reader = try AudioFileReader(path: path)
        let chunk = try reader.readChunk(size: 256)
        #expect(chunk?.count == 256)
    }

    @Test("File size property matches actual file size")
    func fileSizeMatchesActual() throws {
        let path = try createTempFile(ext: "mp3", bytes: 1234)
        defer { removeTempFile(path) }
        let reader = try AudioFileReader(path: path)
        #expect(reader.fileSize == 1234)
    }

    // MARK: - Helpers

    private func createTempFile(ext: String, bytes: Int) throws -> String {
        let dir = NSTemporaryDirectory()
        let name = "test_\(UUID().uuidString).\(ext)"
        let path = (dir as NSString).appendingPathComponent(name)
        let data = Data(repeating: 0xAA, count: bytes)
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    private func removeTempFile(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
