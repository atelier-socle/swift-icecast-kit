// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKit
@testable import IcecastKitCommands

@Suite("TestConnectionCommand")
struct TestConnectionCommandTests {

    // MARK: - Default Values

    @Test("Default host is localhost")
    func defaultHost() throws {
        let cmd = try TestConnectionCommand.parse(["--password", "secret"])
        #expect(cmd.host == "localhost")
    }

    @Test("Default port is 8000")
    func defaultPort() throws {
        let cmd = try TestConnectionCommand.parse(["--password", "secret"])
        #expect(cmd.port == 8000)
    }

    @Test("Default mountpoint is /stream")
    func defaultMountpoint() throws {
        let cmd = try TestConnectionCommand.parse(["--password", "secret"])
        #expect(cmd.mountpoint == "/stream")
    }

    @Test("Default username is source")
    func defaultUsername() throws {
        let cmd = try TestConnectionCommand.parse(["--password", "secret"])
        #expect(cmd.username == "source")
    }

    @Test("Protocol default is auto")
    func defaultProtocol() throws {
        let cmd = try TestConnectionCommand.parse(["--password", "secret"])
        #expect(cmd.protocol == "auto")
    }

    // MARK: - Custom Values

    @Test("Custom host/port/mountpoint parsing")
    func customValues() throws {
        let cmd = try TestConnectionCommand.parse([
            "--host", "radio.example.com",
            "--port", "9000",
            "--mountpoint", "/live.mp3",
            "--password", "secret"
        ])
        #expect(cmd.host == "radio.example.com")
        #expect(cmd.port == 9000)
        #expect(cmd.mountpoint == "/live.mp3")
    }

    @Test("Custom username parsing")
    func customUsername() throws {
        let cmd = try TestConnectionCommand.parse(["--username", "admin", "--password", "secret"])
        #expect(cmd.username == "admin")
    }

    @Test("Password provided parses correctly")
    func passwordParsed() throws {
        let cmd = try TestConnectionCommand.parse(["--password", "mypass"])
        #expect(cmd.password == "mypass")
    }

    // MARK: - Flags

    @Test("tls flag parsing")
    func tlsFlagParsing() throws {
        let cmd = try TestConnectionCommand.parse(["--password", "secret", "--tls"])
        #expect(cmd.tls)
    }

    @Test("no-color flag parsing")
    func noColorFlagParsing() throws {
        let cmd = try TestConnectionCommand.parse(["--password", "secret", "--no-color"])
        #expect(cmd.noColor)
    }

    @Test("Missing password parses but password is nil")
    func missingPasswordParsesAsNil() throws {
        let cmd = try TestConnectionCommand.parse([])
        #expect(cmd.password == nil)
    }

    // MARK: - Auth Type Options

    @Test("Default auth-type is basic")
    func defaultAuthType() throws {
        let cmd = try TestConnectionCommand.parse(["--password", "secret"])
        #expect(cmd.authType == "basic")
    }

    @Test("Auth-type digest parsing")
    func authTypeDigest() throws {
        let cmd = try TestConnectionCommand.parse([
            "--password", "secret", "--auth-type", "digest"
        ])
        #expect(cmd.authType == "digest")
    }

    @Test("Auth-type bearer with token parsing")
    func authTypeBearerWithToken() throws {
        let cmd = try TestConnectionCommand.parse([
            "--auth-type", "bearer", "--token", "my-api-token"
        ])
        #expect(cmd.authType == "bearer")
        #expect(cmd.token == "my-api-token")
    }

    @Test("Auth-type query-token with token parsing")
    func authTypeQueryTokenWithToken() throws {
        let cmd = try TestConnectionCommand.parse([
            "--auth-type", "query-token", "--token", "abc123"
        ])
        #expect(cmd.authType == "query-token")
        #expect(cmd.token == "abc123")
    }

    // MARK: - Exit Code Mapping

    @Test("Auth failure maps to authentication exit code")
    func authFailureExitCode() {
        let code = TestConnectionCommand.mapExitCode(.authenticationFailed(statusCode: 401, message: "Unauthorized"))
        #expect(code == ExitCodes.authenticationError)
    }

    @Test("Connection failure maps to connection exit code")
    func connectionFailureExitCode() {
        let code = TestConnectionCommand.mapExitCode(.connectionFailed(host: "h", port: 8000, reason: "r"))
        #expect(code == ExitCodes.connectionError)
    }

    @Test("Server error maps to server exit code")
    func serverErrorExitCode() {
        let code = TestConnectionCommand.mapExitCode(.mountpointInUse("/live"))
        #expect(code == ExitCodes.serverError)
    }
}
