// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import ArgumentParser
import Foundation
import IcecastKit

/// Test connectivity and authentication to an Icecast/SHOUTcast server.
///
/// Connects, performs protocol negotiation, then immediately disconnects.
/// Reports success/failure and negotiated protocol.
public struct TestConnectionCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "test-connection",
        abstract: "Test connectivity and authentication to a server"
    )

    /// Server hostname.
    @Option(name: .long, help: "Server hostname")
    var host: String = "localhost"

    /// Server port.
    @Option(name: .long, help: "Server port")
    var port: Int = 8000

    /// Mountpoint path.
    @Option(name: .long, help: "Mountpoint path")
    var mountpoint: String = "/stream"

    /// Auth username.
    @Option(name: .long, help: "Auth username")
    var username: String = "source"

    /// Auth password.
    @Option(name: .long, help: "Auth password")
    var password: String?

    /// Protocol mode.
    @Option(
        name: .long,
        help: "Protocol: auto, icecast-put, icecast-source, shoutcast-v1, shoutcast-v2:<id>"
    )
    var `protocol`: String = "auto"

    /// Authentication type.
    @Option(
        name: .long,
        help: "Authentication type: basic, digest, bearer, query-token"
    )
    var authType: String = "basic"

    /// Token value for bearer or query-token authentication.
    @Option(name: .long, help: "Token for --auth-type bearer or query-token")
    var token: String?

    /// Use TLS/HTTPS.
    @Flag(name: .long, help: "Use TLS/HTTPS")
    var tls: Bool = false

    /// Disable colored output.
    @Flag(name: .long, help: "Disable colored output")
    var noColor: Bool = false

    public init() {}

    public mutating func run() async throws {
        let color = ColorOutput(noColor: noColor)
        let progress = ProgressDisplay(color: color)

        let needsPassword = authType == "basic" || authType == "digest"
        if needsPassword {
            guard let password, !password.isEmpty else {
                throw CLIParseError.missingRequiredOption(
                    "--password is required with --auth-type \(authType)"
                )
            }
        }

        let auth = try resolveAuthentication(
            authType: authType, username: username,
            password: password, token: token
        )
        let mode = try parseProtocolMode(self.protocol)
        let config = IcecastConfiguration(
            host: host, port: port, mountpoint: mountpoint,
            useTLS: tls, protocolMode: mode, authentication: auth
        )
        let credentials = IcecastCredentials(
            username: username, password: password ?? ""
        )
        let client = IcecastClient(
            configuration: config, credentials: credentials,
            reconnectPolicy: .none
        )

        do {
            try await client.connect()
            print(
                progress.formatConnected(
                    host: host, port: port,
                    mountpoint: mountpoint, protocolName: self.protocol
                ))
            await client.disconnect()
        } catch let error as IcecastError {
            printError(error: error, progress: progress)
            throw ExitCode(Self.mapExitCode(error))
        }
    }

    private func printError(error: IcecastError, progress: ProgressDisplay) {
        switch error {
        case .authenticationFailed:
            print(progress.formatError("Authentication failed"))
        case .connectionFailed:
            print(progress.formatError("Connection failed: \(error)"))
        case .connectionTimeout:
            print(progress.formatError("Connection timed out"))
        default:
            print(progress.formatError("\(error)"))
        }
    }

    /// Maps an IcecastError to an exit code.
    static func mapExitCode(_ error: IcecastError) -> Int32 {
        switch error {
        case .authenticationFailed, .credentialsRequired:
            return ExitCodes.authenticationError
        case .connectionFailed, .connectionLost, .connectionTimeout:
            return ExitCodes.connectionError
        case .mountpointInUse, .contentTypeNotSupported, .serverError:
            return ExitCodes.serverError
        default:
            return ExitCodes.generalError
        }
    }
}
