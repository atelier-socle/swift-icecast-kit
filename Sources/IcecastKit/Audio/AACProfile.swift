// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// AAC audio profile for ADTS header generation.
///
/// Defines the MPEG-4 Audio Object Type used in the ADTS header.
/// The profile value stored is the MPEG-4 AOT minus 1, as required
/// by the ADTS `profile` field (ISO 13818-7, Table 35).
public enum AACProfile: UInt8, Sendable, Hashable, Codable {
    /// AAC Main profile (AOT 1).
    case main = 0
    /// AAC Low Complexity profile (AOT 2). Most common.
    case lc = 1
    /// AAC Scalable Sample Rate profile (AOT 3).
    case ssr = 2
    /// AAC Long Term Prediction profile (AOT 4).
    case ltp = 3
}
