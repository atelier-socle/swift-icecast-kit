// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKit
@testable import IcecastKitCommands

@Suite("InfoCommand")
struct InfoCommandTests {

    // MARK: - Default Values

    @Test("Default host is localhost")
    func defaultHost() throws {
        let cmd = try InfoCommand.parse(["--admin-pass", "secret"])
        #expect(cmd.host == "localhost")
    }

    @Test("Default port is 8000")
    func defaultPort() throws {
        let cmd = try InfoCommand.parse(["--admin-pass", "secret"])
        #expect(cmd.port == 8000)
    }

    @Test("Default admin-user is admin")
    func defaultAdminUser() throws {
        let cmd = try InfoCommand.parse(["--admin-pass", "secret"])
        #expect(cmd.adminUser == "admin")
    }

    // MARK: - Custom Values

    @Test("Custom admin-user and admin-pass parsing")
    func customAdminCredentials() throws {
        let cmd = try InfoCommand.parse(["--admin-user", "root", "--admin-pass", "topsecret"])
        #expect(cmd.adminUser == "root")
        #expect(cmd.adminPass == "topsecret")
    }

    @Test("Mountpoint optional parsing when provided")
    func mountpointProvided() throws {
        let cmd = try InfoCommand.parse(["--admin-pass", "secret", "--mountpoint", "/live.mp3"])
        #expect(cmd.mountpoint == "/live.mp3")
    }

    @Test("Mountpoint not provided is nil")
    func mountpointNotProvided() throws {
        let cmd = try InfoCommand.parse(["--admin-pass", "secret"])
        #expect(cmd.mountpoint == nil)
    }

    // MARK: - Flags

    @Test("tls flag parsing")
    func tlsFlagParsing() throws {
        let cmd = try InfoCommand.parse(["--admin-pass", "secret", "--tls"])
        #expect(cmd.tls)
    }

    @Test("no-color flag parsing")
    func noColorFlagParsing() throws {
        let cmd = try InfoCommand.parse(["--admin-pass", "secret", "--no-color"])
        #expect(cmd.noColor)
    }

    @Test("Missing admin-pass fails validation")
    func missingAdminPassFails() {
        #expect(throws: Error.self) {
            _ = try InfoCommand.parse([])
        }
    }

    // MARK: - Output Formatting

    @Test("OutputFormatter formats key-value correctly")
    func outputFormatterFormatsCorrectly() {
        let result = OutputFormatter.formatField(key: "Version", value: "2.4.4")
        #expect(result == "  Version: 2.4.4")
    }

    @Test("ServerStats fields are accessible")
    func serverStatsAccessible() {
        let stats = ServerStats(
            serverVersion: "Icecast 2.5.0",
            activeMountpoints: ["/live.mp3"],
            totalListeners: 42,
            totalSources: 2
        )
        #expect(stats.serverVersion == "Icecast 2.5.0")
        #expect(stats.activeMountpoints.count == 1)
        #expect(stats.totalListeners == 42)
        #expect(stats.totalSources == 2)
    }

    @Test("MountStats fields are accessible")
    func mountStatsAccessible() {
        let stats = MountStats(
            mountpoint: "/live.mp3",
            listeners: 10,
            streamTitle: "My Stream",
            bitrate: 128,
            genre: "Rock",
            contentType: "audio/mpeg"
        )
        #expect(stats.mountpoint == "/live.mp3")
        #expect(stats.listeners == 10)
        #expect(stats.streamTitle == "My Stream")
        #expect(stats.bitrate == 128)
    }

    @Test("Exit code mapping for info command errors")
    func exitCodeMapping() {
        #expect(TestConnectionCommand.mapExitCode(.authenticationFailed(statusCode: 401, message: "")) == ExitCodes.authenticationError)
        #expect(TestConnectionCommand.mapExitCode(.connectionFailed(host: "h", port: 1, reason: "r")) == ExitCodes.connectionError)
        #expect(TestConnectionCommand.mapExitCode(.serverError(statusCode: 500, message: "err")) == ExitCodes.serverError)
    }
}
