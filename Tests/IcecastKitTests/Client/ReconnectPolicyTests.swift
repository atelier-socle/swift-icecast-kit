// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("ReconnectPolicy")
struct ReconnectPolicyTests {

    // MARK: - Presets

    @Test("Default preset has correct values")
    func defaultPreset() {
        let policy = ReconnectPolicy.default
        #expect(policy.isEnabled == true)
        #expect(policy.maxRetries == 10)
        #expect(policy.initialDelay == 1.0)
        #expect(policy.maxDelay == 60.0)
        #expect(policy.backoffMultiplier == 2.0)
        #expect(policy.jitterFactor == 0.25)
    }

    @Test("None preset disables reconnection")
    func nonePreset() {
        let policy = ReconnectPolicy.none
        #expect(policy.isEnabled == false)
        #expect(policy.maxRetries == 0)
    }

    @Test("Aggressive preset has correct values")
    func aggressivePreset() {
        let policy = ReconnectPolicy.aggressive
        #expect(policy.isEnabled == true)
        #expect(policy.maxRetries == 20)
        #expect(policy.initialDelay == 0.5)
        #expect(policy.maxDelay == 30.0)
        #expect(policy.backoffMultiplier == 1.5)
        #expect(policy.jitterFactor == 0.1)
    }

    @Test("Conservative preset has correct values")
    func conservativePreset() {
        let policy = ReconnectPolicy.conservative
        #expect(policy.isEnabled == true)
        #expect(policy.maxRetries == 5)
        #expect(policy.initialDelay == 5.0)
        #expect(policy.maxDelay == 120.0)
        #expect(policy.backoffMultiplier == 3.0)
        #expect(policy.jitterFactor == 0.25)
    }

    // MARK: - Delay Calculation

    @Test("Attempt 0 delay is near initialDelay")
    func attempt0Delay() {
        let policy = ReconnectPolicy(jitterFactor: 0.0)
        let delay = policy.delay(forAttempt: 0)
        #expect(delay == 1.0)
    }

    @Test("Attempt 1 delay is initialDelay times backoffMultiplier")
    func attempt1Delay() {
        let policy = ReconnectPolicy(jitterFactor: 0.0)
        let delay = policy.delay(forAttempt: 1)
        #expect(delay == 2.0)
    }

    @Test("Attempt 2 delay is initialDelay times backoffMultiplier squared")
    func attempt2Delay() {
        let policy = ReconnectPolicy(jitterFactor: 0.0)
        let delay = policy.delay(forAttempt: 2)
        #expect(delay == 4.0)
    }

    @Test("High attempt delay is capped at maxDelay")
    func highAttemptCapped() {
        let policy = ReconnectPolicy(maxDelay: 60.0, jitterFactor: 0.0)
        let delay = policy.delay(forAttempt: 100)
        #expect(delay == 60.0)
    }

    @Test("Very high attempt is overflow safe and capped at maxDelay")
    func overflowSafe() {
        let policy = ReconnectPolicy(maxDelay: 60.0, jitterFactor: 0.0)
        let delay = policy.delay(forAttempt: 1000)
        #expect(delay == 60.0)
    }

    @Test("Delay with zero jitter is deterministic")
    func zeroJitterDeterministic() {
        let policy = ReconnectPolicy(jitterFactor: 0.0)
        let delay1 = policy.delay(forAttempt: 3)
        let delay2 = policy.delay(forAttempt: 3)
        #expect(delay1 == delay2)
    }

    @Test("Delay is never negative")
    func delayNeverNegative() {
        let policy = ReconnectPolicy(jitterFactor: 1.0)
        for attempt in 0..<20 {
            let delay = policy.delay(forAttempt: attempt)
            #expect(delay >= 0)
        }
    }

    @Test("Delay with jitter stays within expected range")
    func delayWithJitterRange() {
        let policy = ReconnectPolicy(
            initialDelay: 10.0,
            maxDelay: 100.0,
            backoffMultiplier: 1.0,
            jitterFactor: 0.5
        )
        for _ in 0..<50 {
            let delay = policy.delay(forAttempt: 0)
            #expect(delay >= 5.0)
            #expect(delay <= 15.0)
        }
    }

    // MARK: - Codable

    @Test("Encode and decode roundtrip preserves values")
    func codableRoundtrip() throws {
        let policy = ReconnectPolicy(
            isEnabled: true,
            maxRetries: 5,
            initialDelay: 2.0,
            maxDelay: 30.0,
            backoffMultiplier: 1.5,
            jitterFactor: 0.1
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(policy)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReconnectPolicy.self, from: data)
        #expect(decoded == policy)
    }

    @Test("JSON representation contains expected keys")
    func jsonRepresentation() throws {
        let policy = ReconnectPolicy.default
        let encoder = JSONEncoder()
        let data = try encoder.encode(policy)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["isEnabled"] as? Bool == true)
        #expect(json?["maxRetries"] as? Int == 10)
        #expect(json?["initialDelay"] as? Double == 1.0)
        #expect(json?["maxDelay"] as? Double == 60.0)
        #expect(json?["backoffMultiplier"] as? Double == 2.0)
        #expect(json?["jitterFactor"] as? Double == 0.25)
    }

    // MARK: - Hashable

    @Test("Same values produce equal policies")
    func hashableEqual() {
        let a = ReconnectPolicy(maxRetries: 5, initialDelay: 2.0)
        let b = ReconnectPolicy(maxRetries: 5, initialDelay: 2.0)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Different values produce unequal policies")
    func hashableNotEqual() {
        let a = ReconnectPolicy(maxRetries: 5)
        let b = ReconnectPolicy(maxRetries: 10)
        #expect(a != b)
    }
}
