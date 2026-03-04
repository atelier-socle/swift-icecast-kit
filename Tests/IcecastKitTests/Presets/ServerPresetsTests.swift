// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - Preset Metadata

@Suite("IcecastServerPreset — Metadata")
struct PresetMetadataTests {

    @Test("CaseIterable contains all 7 presets")
    func allCases() {
        #expect(IcecastServerPreset.allCases.count == 7)
    }

    @Test("defaultPort is positive for all presets")
    func defaultPortPositive() {
        for preset in IcecastServerPreset.allCases {
            #expect(preset.defaultPort > 0, "\(preset) has invalid port")
        }
    }

    @Test("defaultMountpoint starts with / for all presets")
    func defaultMountpointStartsWithSlash() {
        for preset in IcecastServerPreset.allCases {
            #expect(
                preset.defaultMountpoint.hasPrefix("/"),
                "\(preset) mountpoint missing /"
            )
        }
    }

    @Test("displayName is non-empty for all presets")
    func displayNameNonEmpty() {
        for preset in IcecastServerPreset.allCases {
            #expect(
                !preset.displayName.isEmpty,
                "\(preset) has empty displayName"
            )
        }
    }

    @Test("presetDescription is non-empty for all presets")
    func descriptionNonEmpty() {
        for preset in IcecastServerPreset.allCases {
            #expect(
                !preset.presetDescription.isEmpty,
                "\(preset) has empty description"
            )
        }
    }
}

// MARK: - Configuration Factory

@Suite("IcecastServerPreset — Configuration Factory")
struct PresetConfigurationFactoryTests {

    @Test("azuracast configuration uses username source")
    func azuracastCredentials() {
        let config = IcecastServerPreset.azuracast.configuration(
            host: "mystation.com", password: "secret"
        )
        #expect(config.credentials?.username == "source")
        #expect(config.credentials?.password == "secret")
        #expect(
            config.authentication
                == .basic(username: "source", password: "secret")
        )
    }

    @Test("radioCo configuration uses bearer authentication")
    func radioCoBearer() {
        let config = IcecastServerPreset.radioCo.configuration(
            host: "mystation.radio.co", password: "api-token"
        )
        #expect(config.authentication == .bearer(token: "api-token"))
    }

    @Test("broadcastify configuration defaults to port 80")
    func broadcastifyPort() {
        let config = IcecastServerPreset.broadcastify.configuration(
            host: "feeds.broadcastify.com", password: "token"
        )
        #expect(config.port == 80)
    }

    @Test("shoutcastDNAS configuration uses shoutcast credentials")
    func shoutcastDNASCredentials() {
        let config = IcecastServerPreset.shoutcastDNAS.configuration(
            host: "myserver.com", password: "sc-pass"
        )
        #expect(config.credentials?.username == "")
        #expect(config.credentials?.password == "sc-pass")
        #expect(config.authentication == .shoutcast(password: "sc-pass"))
        #expect(config.protocolMode == .shoutcastV1)
    }

    @Test("port override replaces preset default")
    func portOverride() {
        let config = IcecastServerPreset.azuracast.configuration(
            host: "mystation.com", port: 8080, password: "secret"
        )
        #expect(config.port == 8080)
    }

    @Test("mountpoint override replaces preset default")
    func mountpointOverride() {
        let config = IcecastServerPreset.azuracast.configuration(
            host: "mystation.com", mountpoint: "/custom.mp3",
            password: "secret"
        )
        #expect(config.mountpoint == "/custom.mp3")
    }

    @Test("contentType propagated to configuration")
    func contentTypePropagated() {
        let config = IcecastServerPreset.icecastOfficial.configuration(
            host: "localhost", password: "hackme",
            contentType: .oggVorbis
        )
        #expect(config.contentType == .oggVorbis)
    }

    @Test("host propagated to configuration")
    func hostPropagated() {
        let config = IcecastServerPreset.libretime.configuration(
            host: "radio.community.org", password: "pass"
        )
        #expect(config.host == "radio.community.org")
    }

    @Test("centovaCast uses shoutcastV2 protocol and credentials")
    func centovaCastShoutcastV2() {
        let config = IcecastServerPreset.centovaCast.configuration(
            host: "panel.centova.com", password: "djpass"
        )
        #expect(config.protocolMode == .shoutcastV2(streamId: 1))
        #expect(
            config.authentication
                == .shoutcastV2(password: "djpass", streamId: 1)
        )
    }

    @Test("libretime uses same pattern as azuracast")
    func libretimeBasicAuth() {
        let config = IcecastServerPreset.libretime.configuration(
            host: "radio.org", password: "pass"
        )
        #expect(config.credentials?.username == "source")
        #expect(config.mountpoint == "/main.mp3")
        #expect(config.protocolMode == .icecastPUT)
    }

    @Test("icecastOfficial uses icecastPUT with basic auth")
    func icecastOfficialConfig() {
        let config = IcecastServerPreset.icecastOfficial.configuration(
            host: "ice.example.com", password: "hackme"
        )
        #expect(config.protocolMode == .icecastPUT)
        #expect(config.mountpoint == "/stream.mp3")
        #expect(
            config.authentication
                == .basic(username: "source", password: "hackme")
        )
    }
}

// MARK: - PresetAuthStyle

@Suite("PresetAuthStyle")
struct PresetAuthStyleTests {

    @Test("CaseIterable covers all 4 styles")
    func allCases() {
        #expect(PresetAuthStyle.allCases.count == 4)
    }

    @Test("each preset maps to correct authenticationStyle")
    func presetAuthStyleMapping() {
        let expected: [IcecastServerPreset: PresetAuthStyle] = [
            .azuracast: .basicAuth,
            .libretime: .basicAuth,
            .radioCo: .bearerToken,
            .centovaCast: .shoutcastV2,
            .shoutcastDNAS: .passwordOnly,
            .icecastOfficial: .basicAuth,
            .broadcastify: .bearerToken
        ]
        for (preset, style) in expected {
            #expect(
                preset.authenticationStyle == style,
                "\(preset) should have \(style)"
            )
        }
    }
}

// MARK: - apply(to:)

@Suite("IcecastServerPreset — apply(to:)")
struct PresetApplyTests {

    @Test("applies default port when config port is unchanged")
    func applyDefaultPort() {
        var config = IcecastConfiguration(
            host: "example.com", mountpoint: "/live.mp3"
        )
        #expect(config.port == 8000)
        IcecastServerPreset.broadcastify.apply(to: &config)
        #expect(config.port == 80)
    }

    @Test("does not overwrite explicitly defined port")
    func preserveExplicitPort() {
        var config = IcecastConfiguration(
            host: "example.com", port: 9090, mountpoint: "/live.mp3"
        )
        IcecastServerPreset.broadcastify.apply(to: &config)
        #expect(config.port == 9090)
    }

    @Test("applies correct auth style")
    func applyAuthStyle() {
        var config = IcecastConfiguration(
            host: "example.com", mountpoint: "/live.mp3",
            credentials: IcecastCredentials(password: "mypass")
        )
        IcecastServerPreset.azuracast.apply(to: &config)
        #expect(
            config.authentication
                == .basic(username: "source", password: "mypass")
        )
        #expect(config.protocolMode == .icecastPUT)
    }

    @Test("apply sets protocol mode")
    func applyProtocolMode() {
        var config = IcecastConfiguration(
            host: "example.com", mountpoint: "/live.mp3",
            credentials: IcecastCredentials(password: "pass")
        )
        IcecastServerPreset.shoutcastDNAS.apply(to: &config)
        #expect(config.protocolMode == .shoutcastV1)
    }

    @Test("apply bearer preset extracts password from credentials")
    func applyBearerFromCredentials() {
        var config = IcecastConfiguration(
            host: "example.com", mountpoint: "/live.mp3",
            credentials: IcecastCredentials(password: "my-token")
        )
        IcecastServerPreset.radioCo.apply(to: &config)
        #expect(config.authentication == .bearer(token: "my-token"))
    }

    @Test("apply bearer preset extracts token from existing auth")
    func applyBearerFromExistingAuth() {
        var config = IcecastConfiguration(
            host: "example.com", mountpoint: "/live.mp3",
            authentication: .bearer(token: "existing-token")
        )
        IcecastServerPreset.broadcastify.apply(to: &config)
        #expect(
            config.authentication == .bearer(token: "existing-token")
        )
    }

    @Test("apply shoutcastV2 preset")
    func applyShoutcastV2() {
        var config = IcecastConfiguration(
            host: "example.com", mountpoint: "/live.mp3",
            credentials: IcecastCredentials(password: "djpass")
        )
        IcecastServerPreset.centovaCast.apply(to: &config)
        #expect(config.protocolMode == .shoutcastV2(streamId: 1))
        #expect(
            config.authentication
                == .shoutcastV2(password: "djpass", streamId: 1)
        )
    }

    @Test("apply passwordOnly preset")
    func applyPasswordOnly() {
        var config = IcecastConfiguration(
            host: "example.com", mountpoint: "/live.mp3",
            credentials: IcecastCredentials(password: "sc-pass")
        )
        IcecastServerPreset.shoutcastDNAS.apply(to: &config)
        #expect(
            config.authentication == .shoutcast(password: "sc-pass")
        )
        #expect(config.credentials?.username == "")
    }
}

// MARK: - Codable

@Suite("IcecastServerPreset — Codable")
struct PresetCodableTests {

    @Test("IcecastServerPreset round-trips through JSON")
    func presetCodableRoundTrip() throws {
        let original = IcecastServerPreset.radioCo
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            IcecastServerPreset.self, from: data
        )
        #expect(decoded == original)
    }

    @Test("PresetAuthStyle round-trips through JSON")
    func authStyleCodableRoundTrip() throws {
        let original = PresetAuthStyle.bearerToken
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            PresetAuthStyle.self, from: data
        )
        #expect(decoded == original)
    }
}

// MARK: - Integration

@Suite("IcecastServerPreset — Integration")
struct PresetIntegrationTests {

    @Test("configuration from each preset creates valid IcecastClient")
    func allPresetsProduceValidConfig() async {
        for preset in IcecastServerPreset.allCases {
            let config = preset.configuration(
                host: "test.example.com", password: "testpass"
            )
            let creds =
                config.credentials
                ?? IcecastCredentials(password: "testpass")
            let client = IcecastClient(
                configuration: config, credentials: creds
            )
            let state = await client.state
            #expect(state == .disconnected)
        }
    }

    @Test("preset configuration passes IcecastClient validation")
    func presetConfigPassesValidation() async {
        let config = IcecastServerPreset.icecastOfficial.configuration(
            host: "ice.example.com", password: "hackme"
        )
        let creds =
            config.credentials
            ?? IcecastCredentials(password: "hackme")
        let client = IcecastClient(
            configuration: config, credentials: creds
        )
        let connected = await client.isConnected
        #expect(!connected)
        #expect(await client.state == .disconnected)
    }
}
