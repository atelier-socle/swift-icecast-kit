// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Target quality hint for auto-configuration via bandwidth probing.
///
/// Controls how aggressively the recommended bitrate approaches the
/// measured upload bandwidth ceiling.
public enum ProbeTargetQuality: String, Sendable, CaseIterable {

    /// Maximize audio quality — uses highest sustainable bitrate.
    ///
    /// Utilization factor: 0.95 (95% of measured bandwidth).
    case quality

    /// Balance quality and reliability — conservative headroom.
    ///
    /// Utilization factor: 0.85 (85% of measured bandwidth).
    case balanced

    /// Minimize latency — uses lower bitrate for smaller buffers
    /// and faster recovery.
    ///
    /// Utilization factor: 0.70 (70% of measured bandwidth).
    case lowLatency

    /// The bandwidth utilization factor for this quality target.
    ///
    /// Determines what fraction of the measured upload bandwidth
    /// should be used for the recommended bitrate.
    public var utilizationFactor: Double {
        switch self {
        case .quality:
            return 0.95
        case .balanced:
            return 0.85
        case .lowLatency:
            return 0.70
        }
    }
}
