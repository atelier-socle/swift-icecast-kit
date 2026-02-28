// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Policy controlling automatic reconnection behavior.
///
/// Supports exponential backoff with configurable jitter to prevent
/// thundering herd problems when multiple clients reconnect simultaneously.
public struct ReconnectPolicy: Sendable, Hashable, Codable {

    /// Whether auto-reconnect is enabled.
    public var isEnabled: Bool

    /// Maximum number of retry attempts before giving up.
    public var maxRetries: Int

    /// Delay before the first retry attempt.
    public var initialDelay: TimeInterval

    /// Maximum delay between retries (caps the exponential growth).
    public var maxDelay: TimeInterval

    /// Multiplier applied to delay on each subsequent attempt.
    public var backoffMultiplier: Double

    /// Random jitter factor (0.0–1.0) to prevent thundering herd.
    ///
    /// Actual delay = calculated delay x (1 ± jitterFactor x random).
    public var jitterFactor: Double

    /// Default policy: enabled, 10 retries, 1s initial, 60s max, 2x backoff, 0.25 jitter.
    public static let `default` = ReconnectPolicy()

    /// Disabled policy: no reconnection.
    public static let none = ReconnectPolicy(
        isEnabled: false,
        maxRetries: 0
    )

    /// Aggressive policy: fast retries, 20 attempts, 0.5s initial, 30s max.
    public static let aggressive = ReconnectPolicy(
        maxRetries: 20,
        initialDelay: 0.5,
        maxDelay: 30.0,
        backoffMultiplier: 1.5,
        jitterFactor: 0.1
    )

    /// Conservative policy: slow retries, 5 attempts, 5s initial, 120s max.
    public static let conservative = ReconnectPolicy(
        maxRetries: 5,
        initialDelay: 5.0,
        maxDelay: 120.0,
        backoffMultiplier: 3.0
    )

    /// Creates a reconnect policy with the given parameters.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether auto-reconnect is enabled. Defaults to `true`.
    ///   - maxRetries: Maximum retry attempts. Defaults to `10`.
    ///   - initialDelay: Initial delay in seconds. Defaults to `1.0`.
    ///   - maxDelay: Maximum delay cap in seconds. Defaults to `60.0`.
    ///   - backoffMultiplier: Delay multiplier per attempt. Defaults to `2.0`.
    ///   - jitterFactor: Jitter factor (0.0–1.0). Defaults to `0.25`.
    public init(
        isEnabled: Bool = true,
        maxRetries: Int = 10,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        backoffMultiplier: Double = 2.0,
        jitterFactor: Double = 0.25
    ) {
        self.isEnabled = isEnabled
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.jitterFactor = jitterFactor
    }

    /// Calculates the delay for a specific attempt number (0-indexed).
    ///
    /// Formula: `min(initialDelay x backoffMultiplier^attempt, maxDelay) x (1 ± jitter)`
    ///
    /// - Parameter attempt: The zero-indexed attempt number.
    /// - Returns: The calculated delay in seconds (never negative).
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let baseDelay = initialDelay * pow(backoffMultiplier, Double(attempt))
        let cappedDelay = min(baseDelay, maxDelay)
        let jitterRange = cappedDelay * jitterFactor
        let jitter = Double.random(in: -jitterRange...jitterRange)
        return max(0, cappedDelay + jitter)
    }
}
