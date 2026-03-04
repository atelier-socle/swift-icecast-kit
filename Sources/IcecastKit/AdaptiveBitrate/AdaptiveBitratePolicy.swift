// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Policy governing adaptive bitrate behavior.
///
/// Provides three built-in presets (conservative, responsive, aggressive)
/// and supports fully custom configurations. Convenience constructors
/// allow overriding min/max bitrate on named presets.
public enum AdaptiveBitratePolicy: Sendable, Hashable, Codable {

    /// Conservative preset — slow adaptation, prioritizes stability.
    case conservative

    /// Responsive preset — balanced adaptation for live content.
    case responsive

    /// Aggressive preset — immediate reaction, for testing/development.
    case aggressive

    /// Fully custom configuration.
    case custom(AdaptiveBitrateConfiguration)

    // MARK: - Convenience Constructors

    /// Creates a responsive policy with custom bitrate bounds.
    ///
    /// - Parameters:
    ///   - min: Minimum bitrate in bits per second.
    ///   - max: Maximum bitrate in bits per second.
    /// - Returns: A responsive policy with the specified bounds.
    public static func responsive(min: Int, max: Int) -> AdaptiveBitratePolicy {
        var config = AdaptiveBitrateConfiguration.responsive
        config.minBitrate = min
        config.maxBitrate = max
        return .custom(config)
    }

    /// Creates a conservative policy with custom bitrate bounds.
    ///
    /// - Parameters:
    ///   - min: Minimum bitrate in bits per second.
    ///   - max: Maximum bitrate in bits per second.
    /// - Returns: A conservative policy with the specified bounds.
    public static func conservative(min: Int, max: Int) -> AdaptiveBitratePolicy {
        var config = AdaptiveBitrateConfiguration.conservative
        config.minBitrate = min
        config.maxBitrate = max
        return .custom(config)
    }

    // MARK: - Configuration Access

    /// The resolved configuration for this policy.
    public var configuration: AdaptiveBitrateConfiguration {
        switch self {
        case .conservative:
            return .conservative
        case .responsive:
            return .responsive
        case .aggressive:
            return .aggressive
        case .custom(let config):
            return config
        }
    }
}
