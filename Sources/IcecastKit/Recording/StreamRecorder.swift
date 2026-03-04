// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Records streaming audio to local files without re-encoding.
///
/// Use cases include local backup, post-production, archives, and compliance.
/// The recorder writes raw audio bytes as received — zero re-encoding overhead.
///
/// Supports automatic file rotation by size or duration, periodic flush to disk,
/// and configurable filename patterns with token substitution.
///
/// Usage:
/// ```swift
/// let config = RecordingConfiguration(
///     directory: "/tmp/recordings",
///     contentType: .mp3,
///     maxFileSize: 50_000_000,
///     splitInterval: 3600
/// )
/// let recorder = StreamRecorder(configuration: config)
/// try await recorder.start()
/// try await recorder.write(audioData)
/// let stats = try await recorder.stop()
/// ```
public actor StreamRecorder {

    // MARK: - Properties

    private let configuration: RecordingConfiguration
    private let rotationPolicy: FileRotationPolicy
    private let fileFactory: any FileHandlingFactory
    private var fileHandle: (any FileHandling)?
    private var currentPath: String?
    private var fileStartDate: Date?
    private var currentFileSize: Int64 = 0
    private var totalBytesWritten: Int64 = 0
    private var filesCreated: Int = 0
    private var recordingStartDate: Date?
    private var recording: Bool = false
    private var fileIndex: Int = 0
    private var flushTask: Task<Void, Never>?
    private var mountpoint: String = ""

    // MARK: - Initialization

    /// Creates a stream recorder with the given configuration.
    ///
    /// - Parameter configuration: The recording configuration.
    public init(configuration: RecordingConfiguration) {
        self.configuration = configuration
        self.rotationPolicy = FileRotationPolicy(
            maxFileSize: configuration.maxFileSize,
            splitInterval: configuration.splitInterval
        )
        self.fileFactory = DefaultFileHandlingFactory()
    }

    /// Creates a stream recorder with the given configuration and file factory.
    ///
    /// - Parameters:
    ///   - configuration: The recording configuration.
    ///   - fileFactory: The factory for creating file handles. Used for testing.
    init(
        configuration: RecordingConfiguration,
        fileFactory: some FileHandlingFactory
    ) {
        self.configuration = configuration
        self.rotationPolicy = FileRotationPolicy(
            maxFileSize: configuration.maxFileSize,
            splitInterval: configuration.splitInterval
        )
        self.fileFactory = fileFactory
    }

    deinit {
        flushTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Starts recording. Creates the output directory if needed.
    ///
    /// - Throws: ``IcecastError/recordingFailed(reason:)`` if already recording,
    ///   or ``IcecastError/recordingDirectoryNotWritable(path:)`` if the directory
    ///   cannot be created or is not writable.
    public func start() async throws {
        guard !recording else {
            throw IcecastError.recordingFailed(reason: "Already recording")
        }

        try ensureDirectory()

        fileIndex = 0
        totalBytesWritten = 0
        filesCreated = 0
        recordingStartDate = Date()
        recording = true

        try openNewFile()
        startFlushTimer()
    }

    /// Starts recording with a mountpoint for filename token resolution.
    ///
    /// - Parameter mountpoint: The mountpoint path (e.g., `"/live.mp3"`).
    /// - Throws: ``IcecastError/recordingFailed(reason:)`` or
    ///   ``IcecastError/recordingDirectoryNotWritable(path:)``.
    public func start(mountpoint: String) async throws {
        self.mountpoint = mountpoint
        try await start()
    }

    /// Stops recording, flushes remaining bytes, and closes the file handle.
    ///
    /// - Returns: Final recording statistics.
    /// - Throws: ``IcecastError/recordingFailed(reason:)`` if an I/O error occurs
    ///   during flush or close.
    @discardableResult
    public func stop() async throws -> RecordingStatistics {
        flushTask?.cancel()
        flushTask = nil

        if let handle = fileHandle {
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                fileHandle = nil
                recording = false
                throw IcecastError.recordingFailed(
                    reason: "Failed to close file: \(error)"
                )
            }
            fileHandle = nil
        }

        recording = false
        let stats = buildStatistics()
        return stats
    }

    // MARK: - Writing

    /// Writes audio bytes to the current recording file.
    ///
    /// Triggers file rotation if the rotation policy is met.
    /// No-op if not recording.
    ///
    /// - Parameter data: The audio data to write.
    /// - Throws: ``IcecastError/recordingFailed(reason:)`` if an I/O error occurs,
    ///   or ``IcecastError/fileRotationFailed(reason:)`` if rotation fails.
    public func write(_ data: Data) async throws {
        guard recording, let handle = fileHandle else { return }

        do {
            try handle.write(contentsOf: data)
        } catch {
            throw IcecastError.recordingFailed(
                reason: "Write failed: \(error)"
            )
        }

        let count = Int64(data.count)
        currentFileSize += count
        totalBytesWritten += count

        let fileDuration = fileStartDate.map { Date().timeIntervalSince($0) } ?? 0
        if rotationPolicy.shouldRotate(
            currentSize: currentFileSize,
            currentDuration: fileDuration
        ) {
            try rotateFile()
        }
    }

    // MARK: - State

    /// Whether recording is currently active.
    public var isRecording: Bool { recording }

    /// Current statistics snapshot.
    public var statistics: RecordingStatistics {
        buildStatistics()
    }

    /// Path of the current recording file. `nil` if not recording.
    public var currentFilePath: String? { currentPath }

    // MARK: - Private Helpers

    /// Ensures the output directory exists and is writable.
    private func ensureDirectory() throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        if fm.fileExists(atPath: configuration.directory, isDirectory: &isDir) {
            guard isDir.boolValue else {
                throw IcecastError.recordingDirectoryNotWritable(
                    path: configuration.directory
                )
            }
            guard fm.isWritableFile(atPath: configuration.directory) else {
                throw IcecastError.recordingDirectoryNotWritable(
                    path: configuration.directory
                )
            }
        } else {
            do {
                try fm.createDirectory(
                    atPath: configuration.directory,
                    withIntermediateDirectories: true
                )
            } catch {
                throw IcecastError.recordingDirectoryNotWritable(
                    path: configuration.directory
                )
            }
        }
    }

    /// Opens a new recording file.
    private func openNewFile() throws {
        fileIndex += 1
        let filename = resolveFilename()
        let ext = fileExtension()
        let path = (configuration.directory as NSString)
            .appendingPathComponent("\(filename).\(ext)")

        guard fileFactory.createFile(atPath: path) else {
            throw IcecastError.recordingFailed(
                reason: "Cannot create file at \(path)"
            )
        }

        guard let handle = fileFactory.open(forWritingAtPath: path) else {
            throw IcecastError.recordingFailed(
                reason: "Cannot open file for writing at \(path)"
            )
        }

        fileHandle = handle
        currentPath = path
        currentFileSize = 0
        fileStartDate = Date()
        filesCreated += 1
    }

    /// Rotates to a new file: flush + close current, open new.
    private func rotateFile() throws {
        guard let handle = fileHandle else { return }

        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            throw IcecastError.fileRotationFailed(
                reason: "Failed to close current file: \(error)"
            )
        }
        fileHandle = nil

        do {
            try openNewFile()
        } catch {
            throw IcecastError.fileRotationFailed(
                reason: "Failed to open new file: \(error)"
            )
        }
    }

    /// Resolves filename tokens in the configured pattern.
    private func resolveFilename() -> String {
        var name = configuration.filenamePattern

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate]
        let dateString = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        name = name.replacingOccurrences(of: "{date}", with: dateString)

        let sanitized = sanitizeMountpoint(mountpoint)
        name = name.replacingOccurrences(of: "{mountpoint}", with: sanitized)

        name = name.replacingOccurrences(of: "{index}", with: "\(fileIndex)")

        return name
    }

    /// Sanitizes a mountpoint for use in filenames.
    private func sanitizeMountpoint(_ mountpoint: String) -> String {
        var result = mountpoint
        if result.hasPrefix("/") {
            result = String(result.dropFirst())
        }
        result = result.replacingOccurrences(of: "/", with: "_")
        result = result.replacingOccurrences(of: ".", with: "_")
        return result.isEmpty ? "stream" : result
    }

    /// Returns the file extension based on format and content type.
    private func fileExtension() -> String {
        switch configuration.format {
        case .matchSource:
            return configuration.contentType.fileExtension
        case .raw:
            return "raw"
        }
    }

    /// Builds statistics from current state.
    private func buildStatistics() -> RecordingStatistics {
        let duration: TimeInterval
        if let start = recordingStartDate {
            duration = Date().timeIntervalSince(start)
        } else {
            duration = 0
        }

        return RecordingStatistics(
            duration: duration,
            bytesWritten: totalBytesWritten,
            filesCreated: filesCreated,
            currentFilePath: currentPath,
            isRecording: recording
        )
    }

    /// Starts the periodic flush timer.
    private func startFlushTimer() {
        let interval = configuration.flushInterval
        guard interval > 0 else { return }

        flushTask = Task { [weak self] in
            let nanoseconds = UInt64(interval * 1_000_000_000)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                await self.flush()
            }
        }
    }

    /// Flushes the file handle to disk.
    private func flush() {
        guard let handle = fileHandle else { return }
        try? handle.synchronize()
    }
}
