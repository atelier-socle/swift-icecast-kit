// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKit

@Suite("Showcase — Server Presets")
struct ServerPresetsShowcaseTests {

    // MARK: - Showcase 1: AzuraCast preset

    @Test("AzuraCast preset configures source username and basic auth")
    func azuracastPresetConfiguresSourceUsername() {
        let config = IcecastServerPreset.azuracast.configuration(
            host: "mystation.azuracast.com",
            password: "my-source-password"
        )
        #expect(config.credentials?.username == "source")
        #expect(config.credentials?.password == "my-source-password")
        #expect(config.mountpoint == "/radio.mp3")
        #expect(config.protocolMode == .icecastPUT)
    }

    // MARK: - Showcase 2: Radio.co uses bearer auth

    @Test("Radio.co preset uses bearer token authentication")
    func radioCoPresetUsesBearerAuth() {
        let preset = IcecastServerPreset.radioCo
        #expect(preset.authenticationStyle == .bearerToken)

        let config = preset.configuration(
            host: "streaming.radio.co",
            password: "api-token-xyz"
        )
        if case .bearer(let token) = config.authentication {
            #expect(token == "api-token-xyz")
        } else {
            Issue.record("Expected bearer authentication")
        }
    }

    // MARK: - Showcase 3: Broadcastify uses port 80

    @Test("Broadcastify preset defaults to port 80")
    func broadcastifyPresetUsesPort80() {
        let preset = IcecastServerPreset.broadcastify
        #expect(preset.defaultPort == 80)

        let config = preset.configuration(
            host: "audio.broadcastify.com",
            password: "feed-password"
        )
        #expect(config.port == 80)
    }

    // MARK: - Showcase 4: SHOUTcast DNAS password-only

    @Test("SHOUTcast DNAS preset uses password-only auth")
    func shoutcastDNASPresetUsesPasswordOnlyAuth() {
        let preset = IcecastServerPreset.shoutcastDNAS
        #expect(preset.authenticationStyle == .passwordOnly)
        #expect(preset.protocolMode == .shoutcastV1)

        let config = preset.configuration(
            host: "sc.example.com",
            password: "djpass"
        )
        if case .shoutcast = config.authentication {
            // correct
        } else {
            Issue.record("Expected shoutcast authentication")
        }
    }

    // MARK: - Showcase 5: Centova Cast SHOUTcast v2

    @Test("Centova Cast preset uses SHOUTcast v2 dialect")
    func centovaCastPresetUsesShoutcastV2() {
        let preset = IcecastServerPreset.centovaCast
        #expect(preset.authenticationStyle == .shoutcastV2)

        if case .shoutcastV2(let streamId) = preset.protocolMode {
            #expect(streamId == 1)
        } else {
            Issue.record("Expected shoutcastV2 protocol mode")
        }
    }

    // MARK: - Showcase 6: Port override respected

    @Test("Port override respected for all presets")
    func portOverrideRespectedForAllPresets() {
        for preset in IcecastServerPreset.allCases {
            let config = preset.configuration(
                host: "test.example.com",
                port: 9999,
                password: "test"
            )
            #expect(config.port == 9999)
        }
    }

    // MARK: - Showcase 7: Mountpoint override respected

    @Test("Mountpoint override respected for all presets")
    func mountpointOverrideRespected() {
        for preset in IcecastServerPreset.allCases {
            let config = preset.configuration(
                host: "test.example.com",
                mountpoint: "/custom.mp3",
                password: "test"
            )
            #expect(config.mountpoint == "/custom.mp3")
        }
    }

    // MARK: - Showcase 8: ContentType propagated

    @Test("Content type propagated correctly through preset")
    func contentTypePropagatedCorrectly() {
        let config = IcecastServerPreset.azuracast.configuration(
            host: "radio.example.com",
            password: "secret",
            contentType: .aac
        )
        #expect(config.contentType == .aac)
    }

    // MARK: - Showcase 9: apply(to:) modifies existing configuration

    @Test("apply(to:) modifies existing configuration with preset defaults")
    func applyToModifiesExistingConfiguration() {
        var config = IcecastConfiguration(
            host: "radio.example.com",
            mountpoint: "/live.mp3",
            credentials: IcecastCredentials(password: "secret")
        )

        IcecastServerPreset.broadcastify.apply(to: &config)
        #expect(config.port == 80)
        #expect(config.protocolMode == .icecastPUT)
        // Bearer auth applied for broadcastify
        if case .bearer = config.authentication {
            // correct
        } else {
            Issue.record("Expected bearer authentication from broadcastify preset")
        }
    }

    // MARK: - Showcase 10: All presets produce valid configuration

    @Test("All 7 presets produce a valid configuration")
    func allPresetsProduceValidConfiguration() {
        let presets = IcecastServerPreset.allCases
        #expect(presets.count == 7)

        for preset in presets {
            let config = preset.configuration(
                host: "test.example.com",
                password: "testpass"
            )
            #expect(!config.host.isEmpty)
            #expect(!config.mountpoint.isEmpty)
            #expect(config.port > 0)

            // Verify display metadata
            #expect(!preset.displayName.isEmpty)
            #expect(!preset.presetDescription.isEmpty)
        }
    }

    // MARK: - Showcase 11: LibreTime preset

    @Test("LibreTime preset uses basic auth and /main.mp3 mountpoint")
    func libretimePreset() {
        let preset = IcecastServerPreset.libretime
        #expect(preset.defaultMountpoint == "/main.mp3")
        #expect(preset.authenticationStyle == .basicAuth)

        let config = preset.configuration(
            host: "libre.example.com",
            password: "hackme"
        )
        #expect(config.credentials?.username == "source")
    }

    // MARK: - Showcase 12: Icecast official preset

    @Test("Icecast official preset uses standard defaults")
    func icecastOfficialPreset() {
        let preset = IcecastServerPreset.icecastOfficial
        #expect(preset.defaultPort == 8000)
        #expect(preset.defaultMountpoint == "/stream.mp3")
        #expect(preset.protocolMode == .icecastPUT)
        #expect(preset.authenticationStyle == .basicAuth)
    }

    // MARK: - Showcase 13: extractPassword for digest and shoutcast auth

    @Test("extractPassword returns password for digest, shoutcast, bearer, and nil for queryToken")
    func extractPasswordCoversAllAuthCases() {
        let digest = IcecastAuthentication.digest(username: "admin", password: "secret")
        #expect(digest.extractPassword == "secret")

        let sc = IcecastAuthentication.shoutcast(password: "djpass")
        #expect(sc.extractPassword == "djpass")

        let sc2 = IcecastAuthentication.shoutcastV2(password: "pass", streamId: 1)
        #expect(sc2.extractPassword == "pass")

        let bearer = IcecastAuthentication.bearer(token: "tok123")
        #expect(bearer.extractPassword == "tok123")

        let qt = IcecastAuthentication.queryToken(key: "k", value: "v")
        #expect(qt.extractPassword == nil)
    }

    // MARK: - Showcase 14: apply(to:) extracts password from digest authentication

    @Test("apply(to:) extracts password from authentication when credentials are nil")
    func applyExtractsPasswordFromAuth() {
        var config = IcecastConfiguration(
            host: "radio.example.com",
            mountpoint: "/live.mp3"
        )
        config.authentication = .digest(username: "admin", password: "mypass")

        IcecastServerPreset.icecastOfficial.apply(to: &config)
        #expect(config.credentials?.password == "mypass")
    }
}
