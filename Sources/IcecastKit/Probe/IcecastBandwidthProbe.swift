// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Measures available upload bandwidth to an Icecast server.
///
/// Connects as a SOURCE client, sends test audio data at progressively
/// increasing bitrates, measures write latency at each step, detects
/// the saturation point, then disconnects cleanly.
///
/// Usage:
/// ```swift
/// let probe = IcecastBandwidthProbe()
/// let result = try await probe.measure(
///     host: "radio.example.com",
///     port: 8000,
///     mountpoint: "/probe",
///     credentials: IcecastCredentials(password: "secret"),
///     contentType: .mp3
/// )
/// print("Bandwidth: \(result.uploadBandwidth) bps")
/// print("Recommended: \(result.recommendedBitrate) bps")
/// ```
public actor IcecastBandwidthProbe {

    private let connectionFactory: @Sendable () -> any TransportConnection

    /// Creates a new bandwidth probe.
    public init() {
        self.connectionFactory = TransportConnectionFactory.makeConnection
    }

    /// Creates a new bandwidth probe with a custom connection factory.
    ///
    /// - Parameter connectionFactory: A factory closure for creating transport connections.
    init(connectionFactory: @Sendable @escaping () -> any TransportConnection) {
        self.connectionFactory = connectionFactory
    }

    /// Measures available upload bandwidth to an Icecast server.
    ///
    /// Connects to the server as a SOURCE client on the given mountpoint,
    /// sends test audio data at progressively increasing bitrates, measures
    /// write latency at each step, detects saturation, then disconnects cleanly.
    ///
    /// - Parameters:
    ///   - host: Icecast server hostname.
    ///   - port: Icecast server port.
    ///   - mountpoint: Mountpoint to use for the probe (e.g., `"/probe"`).
    ///   - credentials: Source credentials for authentication.
    ///   - contentType: Audio content type to announce (affects headers only).
    ///   - duration: Total probe duration in seconds (default: 5.0, min: 2.0, max: 30.0).
    /// - Returns: Probe result with bandwidth estimate and recommendations.
    /// - Throws: ``IcecastError/probeFailed(reason:)`` or ``IcecastError/probeTimeout``.
    public func measure(
        host: String,
        port: Int = 8000,
        mountpoint: String,
        credentials: IcecastCredentials,
        contentType: AudioContentType = .mp3,
        duration: TimeInterval = 5.0
    ) async throws -> IcecastProbeResult {
        let clampedDuration = min(max(duration, 2.0), 30.0)
        let steps = AudioQualityStep.steps(for: contentType).reversed()
        let stepsArray = Array(steps)

        guard !stepsArray.isEmpty else {
            throw IcecastError.probeFailed(reason: "No quality steps for \(contentType.rawValue)")
        }

        let config = IcecastConfiguration(
            host: host, port: port, mountpoint: mountpoint,
            contentType: contentType
        )
        let transport = connectionFactory()

        let startTime = Date()
        var serverVersion: String?

        do {
            try await transport.connect(host: host, port: port, useTLS: false)
            serverVersion = try await negotiateAndExtractVersion(
                transport: transport, configuration: config, credentials: credentials
            )
        } catch {
            await transport.close()
            throw IcecastError.probeFailed(reason: "Connection failed: \(error)")
        }

        let silenceFrame = generateSilenceFrame(contentType: contentType)
        let probeData: [StepMeasurement]
        do {
            probeData = try await runProbeRamp(
                transport: transport,
                steps: stepsArray,
                duration: clampedDuration,
                silenceFrame: silenceFrame
            )
        } catch {
            await transport.close()
            throw error
        }

        await transport.close()

        let actualDuration = Date().timeIntervalSince(startTime)
        return buildResult(
            probeData: probeData,
            contentType: contentType,
            actualDuration: actualDuration,
            serverVersion: serverVersion
        )
    }

    // MARK: - Protocol Negotiation

    /// Negotiates the SOURCE protocol and extracts server version.
    private func negotiateAndExtractVersion(
        transport: any TransportConnection,
        configuration: IcecastConfiguration,
        credentials: IcecastCredentials
    ) async throws -> String? {
        let negotiator = ProtocolNegotiator(connectionFactory: connectionFactory)
        _ = try await negotiator.negotiate(
            connection: transport,
            configuration: configuration,
            credentials: credentials
        )
        return nil
    }

    // MARK: - Probe Ramp

    /// Per-step measurement data collected during the probe.
    private struct StepMeasurement {
        let stepBitrate: Int
        var writeLatencies: [Double] = []
        var achievedBps: [Double] = []
        var saturated: Bool = false
    }

    /// Runs the progressive bitrate ramp and collects measurements.
    private func runProbeRamp(
        transport: any TransportConnection,
        steps: [AudioQualityStep],
        duration: TimeInterval,
        silenceFrame: Data
    ) async throws -> [StepMeasurement] {
        let stepDuration = duration / Double(steps.count)
        var measurements: [StepMeasurement] = []
        var previousMedianLatency: Double?

        for step in steps {
            var measurement = StepMeasurement(stepBitrate: step.bitrate)
            let stepStart = Date()

            let bytesPerSecond = Double(step.bitrate) / 8.0
            let chunkSize = silenceFrame.count
            let targetBytesPerStep = Int(bytesPerSecond * stepDuration)
            var bytesSent = 0

            while bytesSent < targetBytesPerStep {
                let elapsed = Date().timeIntervalSince(stepStart)
                if elapsed >= stepDuration { break }

                let writeStart = Date()
                do {
                    try await transport.send(silenceFrame)
                } catch {
                    throw IcecastError.probeFailed(
                        reason: "Write failed at \(step.label): \(error)"
                    )
                }
                let writeDuration = Date().timeIntervalSince(writeStart)
                let latencyMs = writeDuration * 1000.0

                measurement.writeLatencies.append(latencyMs)
                if writeDuration > 0 {
                    let bps = Double(chunkSize * 8) / writeDuration
                    measurement.achievedBps.append(bps)
                }

                bytesSent += chunkSize
            }

            if let prevMedian = previousMedianLatency,
                !measurement.writeLatencies.isEmpty
            {
                let currentMedian = median(measurement.writeLatencies)
                if currentMedian > prevMedian * 3.0 {
                    measurement.saturated = true
                    measurements.append(measurement)
                    break
                }
            }

            if !measurement.writeLatencies.isEmpty {
                previousMedianLatency = median(measurement.writeLatencies)
            }
            measurements.append(measurement)
        }

        guard !measurements.isEmpty,
            measurements.contains(where: { !$0.writeLatencies.isEmpty })
        else {
            throw IcecastError.probeFailed(reason: "No measurements collected")
        }

        return measurements
    }

    // MARK: - Result Computation

    /// Builds the final probe result from collected measurements.
    private func buildResult(
        probeData: [StepMeasurement],
        contentType: AudioContentType,
        actualDuration: TimeInterval,
        serverVersion: String?
    ) -> IcecastProbeResult {
        let lastStable = lastStableStep(probeData)
        let uploadBandwidth = ewmaAverage(lastStable.achievedBps, alpha: 0.3)

        let allLatencies = probeData.flatMap(\.writeLatencies)
        let avgLatency =
            allLatencies.isEmpty
            ? 0 : allLatencies.reduce(0, +) / Double(allLatencies.count)
        let latencyVar = variance(allLatencies)

        let stabRatio =
            avgLatency > 0
            ? min(max(latencyVar / avgLatency, 0), 1) : 0
        let stabilityScore = 100.0 * (1.0 - stabRatio)

        let targetBandwidth = uploadBandwidth * 0.85
        let recommended = AudioQualityStep.closestStep(
            for: Int(targetBandwidth), contentType: contentType
        )
        let recommendedBitrate =
            recommended?.bitrate
            ?? AudioQualityStep.steps(for: contentType).last?.bitrate ?? 32_000

        let latencyClass = IcecastProbeResult.LatencyClass.classify(avgLatency)

        return IcecastProbeResult(
            uploadBandwidth: uploadBandwidth,
            averageWriteLatency: avgLatency,
            writeLatencyVariance: latencyVar,
            stabilityScore: stabilityScore,
            recommendedBitrate: recommendedBitrate,
            latencyClass: latencyClass,
            duration: actualDuration,
            serverVersion: serverVersion
        )
    }

    /// Returns the last non-saturated step, or the first step if all saturated.
    private func lastStableStep(_ data: [StepMeasurement]) -> StepMeasurement {
        let stableSteps = data.filter { !$0.saturated }
        return stableSteps.last ?? data[0]
    }

    // MARK: - Statistics Helpers

    /// Computes the median of a sorted array.
    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count
        guard count > 0 else { return 0 }
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        }
        return sorted[count / 2]
    }

    /// Computes the variance of an array of values.
    private func variance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sumSquares = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return sumSquares / Double(values.count)
    }

    /// Computes an EWMA average over a sequence of values.
    private func ewmaAverage(_ values: [Double], alpha: Double) -> Double {
        guard let first = values.first else { return 0 }
        var ewma = first
        for value in values.dropFirst() {
            ewma = alpha * value + (1 - alpha) * ewma
        }
        return ewma
    }

    // MARK: - Test Data Generation

    /// Generates a minimal silence frame for the given content type.
    ///
    /// For MP3: a valid MPEG1 Layer3 frame header followed by silence bytes.
    /// Frame size: 417 bytes at 128kbps/44.1kHz.
    /// Other formats use a similar-sized silent frame pattern.
    private func generateSilenceFrame(contentType: AudioContentType) -> Data {
        switch contentType {
        case .mp3:
            return generateMP3SilenceFrame()
        case .aac:
            return generateAACSilenceFrame()
        default:
            return generateGenericSilenceFrame()
        }
    }

    /// Generates a valid MP3 silence frame (MPEG1 Layer3, 128kbps, 44.1kHz).
    ///
    /// Frame structure: 4-byte header + 413 bytes of silence data = 417 bytes.
    /// Header: 0xFF 0xFB 0x90 0x00 (sync, MPEG1, Layer3, 128kbps, 44.1kHz, stereo).
    private func generateMP3SilenceFrame() -> Data {
        let frameSize = 417
        var frame = Data(count: frameSize)
        frame[0] = 0xFF  // Frame sync
        frame[1] = 0xFB  // MPEG1, Layer3, no CRC
        frame[2] = 0x90  // 128kbps, 44.1kHz, no padding
        frame[3] = 0x00  // Stereo, no emphasis
        return frame
    }

    /// Generates a minimal AAC ADTS silence frame.
    ///
    /// ADTS header (7 bytes) followed by silence payload.
    private func generateAACSilenceFrame() -> Data {
        let frameSize = 400
        var frame = Data(count: frameSize)
        frame[0] = 0xFF  // Sync word
        frame[1] = 0xF1  // MPEG-4, Layer 0, no CRC
        frame[2] = 0x50  // AAC-LC, 44.1kHz
        frame[3] = 0x80  // Stereo, frame length MSB
        let length = frameSize
        frame[3] |= UInt8((length >> 11) & 0x03)
        frame[4] = UInt8((length >> 3) & 0xFF)
        frame[5] = UInt8((length & 0x07) << 5) | 0x1F
        frame[6] = 0xFC  // Buffer fullness
        return frame
    }

    /// Generates a generic silence frame for formats without specific encoding.
    private func generateGenericSilenceFrame() -> Data {
        Data(count: 417)
    }
}
