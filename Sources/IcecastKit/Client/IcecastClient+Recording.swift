// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

// MARK: - Recording

extension IcecastClient {

    /// Starts recording to the given directory.
    ///
    /// Creates a ``StreamRecorder`` with a ``RecordingConfiguration``
    /// using the client's content type and starts recording immediately.
    ///
    /// - Parameters:
    ///   - directory: Output directory path.
    ///   - contentType: Audio content type. Defaults to the configuration's content type.
    /// - Throws: ``IcecastError/recordingFailed(reason:)`` if already recording,
    ///   or ``IcecastError/recordingDirectoryNotWritable(path:)`` if the directory
    ///   cannot be created.
    public func startRecording(
        directory: String,
        contentType: AudioContentType? = nil
    ) async throws {
        let recordConfig = RecordingConfiguration(
            directory: directory,
            contentType: contentType ?? configuration.contentType
        )
        let newRecorder = StreamRecorder(configuration: recordConfig)
        try await newRecorder.start(mountpoint: configuration.mountpoint)
        recorder = newRecorder
        if let path = await newRecorder.currentFilePath {
            await monitor.emit(.recordingStarted(path: path))
        }
    }

    /// Stops recording and returns final statistics.
    ///
    /// - Returns: Final recording statistics.
    /// - Throws: ``IcecastError/recordingFailed(reason:)`` if an I/O error occurs.
    @discardableResult
    public func stopRecording() async throws -> RecordingStatistics {
        guard let activeRecorder = recorder else {
            return RecordingStatistics(
                duration: 0,
                bytesWritten: 0,
                filesCreated: 0,
                currentFilePath: nil,
                isRecording: false
            )
        }
        let stats = try await activeRecorder.stop()
        recorder = nil
        await monitor.emit(.recordingStopped(statistics: stats))
        return stats
    }

    /// Current recording statistics. `nil` if not recording.
    public var recordingStatistics: RecordingStatistics? {
        get async {
            guard let activeRecorder = recorder else { return nil }
            let stats = await activeRecorder.statistics
            return stats.isRecording ? stats : nil
        }
    }

    /// Starts recording automatically if configuration includes recording settings.
    func startRecordingIfConfigured() async {
        guard let recordConfig = configuration.recording else { return }
        let newRecorder = StreamRecorder(configuration: recordConfig)
        do {
            try await newRecorder.start(mountpoint: configuration.mountpoint)
            recorder = newRecorder
            if let path = await newRecorder.currentFilePath {
                await monitor.emit(.recordingStarted(path: path))
            }
        } catch {
            await monitor.emit(
                .recordingError(mapToIcecastError(error))
            )
        }
    }

    /// Stops the recorder if active, emitting appropriate events.
    func stopRecorderIfActive() async {
        guard let activeRecorder = recorder else { return }
        do {
            let stats = try await activeRecorder.stop()
            recorder = nil
            await monitor.emit(.recordingStopped(statistics: stats))
        } catch {
            recorder = nil
            await monitor.emit(
                .recordingError(mapToIcecastError(error))
            )
        }
    }

    /// Writes data to the recorder, handling rotation events.
    func writeToRecorder(_ data: Data) async {
        guard let activeRecorder = recorder else { return }
        let pathBefore = await activeRecorder.currentFilePath
        do {
            try await activeRecorder.write(data)
            let pathAfter = await activeRecorder.currentFilePath
            if let newPath = pathAfter, newPath != pathBefore {
                await monitor.emit(.recordingFileRotated(newPath: newPath))
            }
        } catch {
            await monitor.emit(
                .recordingError(mapToIcecastError(error))
            )
        }
    }
}
