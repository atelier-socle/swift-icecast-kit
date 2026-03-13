// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("AudioConfiguration")
struct AudioConfigurationTests {

    @Test("Sample rate index for standard rates")
    func sampleRateIndexStandard() {
        let rates: [(Int, UInt8)] = [
            (96000, 0), (88200, 1), (64000, 2), (48000, 3),
            (44100, 4), (32000, 5), (24000, 6), (22050, 7),
            (16000, 8), (12000, 9), (11025, 10), (8000, 11),
            (7350, 12)
        ]
        for (rate, expectedIndex) in rates {
            let config = AudioConfiguration(sampleRate: rate, channelCount: 2)
            #expect(config.sampleRateIndex == expectedIndex)
        }
    }

    @Test("Unsupported sample rate returns nil index")
    func unsupportedSampleRate() {
        let config = AudioConfiguration(sampleRate: 43000, channelCount: 2)
        #expect(config.sampleRateIndex == nil)
    }

    @Test("Default profile is AAC-LC")
    func defaultProfile() {
        let config = AudioConfiguration(sampleRate: 44100, channelCount: 2)
        #expect(config.profile == .lc)
    }

    @Test("Custom profile preserved")
    func customProfile() {
        let config = AudioConfiguration(sampleRate: 44100, channelCount: 2, profile: .main)
        #expect(config.profile == .main)
    }

    @Test("Equatable conformance")
    func equatable() {
        let a = AudioConfiguration(sampleRate: 44100, channelCount: 2)
        let b = AudioConfiguration(sampleRate: 44100, channelCount: 2)
        let c = AudioConfiguration(sampleRate: 48000, channelCount: 2)
        #expect(a == b)
        #expect(a != c)
    }
}

@Suite("AACProfile")
struct AACProfileTests {

    @Test("Raw values match ADTS spec")
    func rawValues() {
        #expect(AACProfile.main.rawValue == 0)
        #expect(AACProfile.lc.rawValue == 1)
        #expect(AACProfile.ssr.rawValue == 2)
        #expect(AACProfile.ltp.rawValue == 3)
    }

    @Test("Codable round-trip")
    func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for profile in [AACProfile.main, .lc, .ssr, .ltp] {
            let data = try encoder.encode(profile)
            let decoded = try decoder.decode(AACProfile.self, from: data)
            #expect(decoded == profile)
        }
    }
}
