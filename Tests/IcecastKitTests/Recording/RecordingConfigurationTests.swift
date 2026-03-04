// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - RecordingConfiguration Tests

@Suite("RecordingConfiguration")
struct RecordingConfigurationTests {

    @Test("default has sensible values")
    func defaultConfiguration() {
        let config = RecordingConfiguration.default
        #expect(config.directory == ".")
        #expect(config.format == .matchSource)
        #expect(config.maxFileSize == nil)
        #expect(config.splitInterval == nil)
        #expect(config.flushInterval == 1.0)
        #expect(!config.filenamePattern.isEmpty)
        #expect(config.contentType == .mp3)
    }

    @Test("custom init sets all properties")
    func customInit() {
        let config = RecordingConfiguration(
            directory: "/tmp/rec",
            contentType: .aac,
            format: .raw,
            maxFileSize: 1_000_000,
            splitInterval: 600,
            flushInterval: 2.0,
            filenamePattern: "{date}_{index}"
        )
        #expect(config.directory == "/tmp/rec")
        #expect(config.contentType == .aac)
        #expect(config.format == .raw)
        #expect(config.maxFileSize == 1_000_000)
        #expect(config.splitInterval == 600)
        #expect(config.flushInterval == 2.0)
        #expect(config.filenamePattern == "{date}_{index}")
    }
}

// MARK: - RecordingFormat Tests

@Suite("RecordingFormat")
struct RecordingFormatTests {

    @Test("CaseIterable covers all formats")
    func allCases() {
        #expect(RecordingFormat.allCases.count == 2)
    }

    @Test("rawValue round-trips")
    func rawValues() {
        #expect(RecordingFormat(rawValue: "matchSource") == .matchSource)
        #expect(RecordingFormat(rawValue: "raw") == .raw)
    }
}

// MARK: - AudioContentType File Extension Tests

@Suite("AudioContentType — File Extension")
struct AudioContentTypeFileExtensionTests {

    @Test("mp3 returns mp3")
    func mp3Extension() {
        #expect(AudioContentType.mp3.fileExtension == "mp3")
    }

    @Test("aac returns aac")
    func aacExtension() {
        #expect(AudioContentType.aac.fileExtension == "aac")
    }

    @Test("oggVorbis returns ogg")
    func oggVorbisExtension() {
        #expect(AudioContentType.oggVorbis.fileExtension == "ogg")
    }

    @Test("oggOpus returns opus")
    func oggOpusExtension() {
        #expect(AudioContentType.oggOpus.fileExtension == "opus")
    }

    @Test("unknown content type returns raw")
    func unknownExtension() {
        let custom = AudioContentType(rawValue: "audio/flac")
        #expect(custom.fileExtension == "raw")
    }
}

// MARK: - FileRotationPolicy Tests

@Suite("FileRotationPolicy")
struct FileRotationPolicyTests {

    @Test("shouldRotate returns false when under both thresholds")
    func underThresholds() {
        let policy = FileRotationPolicy(
            maxFileSize: 1000, splitInterval: 60
        )
        #expect(!policy.shouldRotate(currentSize: 500, currentDuration: 30))
    }

    @Test("shouldRotate returns true when size threshold reached")
    func sizeThreshold() {
        let policy = FileRotationPolicy(maxFileSize: 1000)
        #expect(policy.shouldRotate(currentSize: 1000, currentDuration: 0))
        #expect(policy.shouldRotate(currentSize: 1500, currentDuration: 0))
    }

    @Test("shouldRotate returns true when time threshold reached")
    func timeThreshold() {
        let policy = FileRotationPolicy(splitInterval: 60)
        #expect(policy.shouldRotate(currentSize: 0, currentDuration: 60))
        #expect(policy.shouldRotate(currentSize: 0, currentDuration: 120))
    }

    @Test("shouldRotate with combined policy triggers on either")
    func combinedPolicy() {
        let policy = FileRotationPolicy(
            maxFileSize: 1000, splitInterval: 60
        )
        #expect(policy.shouldRotate(currentSize: 1000, currentDuration: 10))
        #expect(policy.shouldRotate(currentSize: 100, currentDuration: 60))
    }

    @Test("none never rotates")
    func nonePolicy() {
        let policy = FileRotationPolicy.none
        #expect(!policy.shouldRotate(currentSize: 999_999_999, currentDuration: 999_999))
    }

    @Test("hourly rotates at 3600 seconds")
    func hourlyPolicy() {
        let policy = FileRotationPolicy.hourly
        #expect(!policy.shouldRotate(currentSize: 0, currentDuration: 3599))
        #expect(policy.shouldRotate(currentSize: 0, currentDuration: 3600))
    }

    @Test("every(_:) rotates at the given interval")
    func everyPolicy() {
        let policy = FileRotationPolicy.every(300)
        #expect(!policy.shouldRotate(currentSize: 0, currentDuration: 299))
        #expect(policy.shouldRotate(currentSize: 0, currentDuration: 300))
    }

    @Test("maxSize(_:) rotates at the given size")
    func maxSizePolicy() {
        let policy = FileRotationPolicy.maxSize(5000)
        #expect(!policy.shouldRotate(currentSize: 4999, currentDuration: 0))
        #expect(policy.shouldRotate(currentSize: 5000, currentDuration: 0))
    }
}

// MARK: - RecordingStatistics Tests

@Suite("RecordingStatistics")
struct RecordingStatisticsTests {

    @Test("All fields are accessible")
    func fields() {
        let stats = RecordingStatistics(
            duration: 120.5,
            bytesWritten: 1_000_000,
            filesCreated: 3,
            currentFilePath: "/tmp/rec/file.mp3",
            isRecording: true
        )
        #expect(stats.duration == 120.5)
        #expect(stats.bytesWritten == 1_000_000)
        #expect(stats.filesCreated == 3)
        #expect(stats.currentFilePath == "/tmp/rec/file.mp3")
        #expect(stats.isRecording)
    }
}

// MARK: - IcecastError Recording Cases Tests

@Suite("IcecastError — Recording Cases")
struct IcecastErrorRecordingTests {

    @Test("recordingFailed description")
    func recordingFailedDesc() {
        let error = IcecastError.recordingFailed(reason: "disk full")
        #expect(error.description.contains("disk full"))
    }

    @Test("fileRotationFailed description")
    func fileRotationFailedDesc() {
        let error = IcecastError.fileRotationFailed(reason: "permission denied")
        #expect(error.description.contains("permission denied"))
    }

    @Test("recordingDirectoryNotWritable description")
    func dirNotWritableDesc() {
        let error = IcecastError.recordingDirectoryNotWritable(path: "/root/nope")
        #expect(error.description.contains("/root/nope"))
    }
}
