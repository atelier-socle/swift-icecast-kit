// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import ArgumentParser

/// Root command for the icecast-cli tool.
///
/// Provides subcommands for streaming audio, testing connections,
/// and retrieving server information.
public struct IcecastKitCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "icecast-cli",
        abstract: "Stream audio to Icecast and SHOUTcast servers",
        version: "0.3.0",
        subcommands: [
            StreamCommand.self,
            TestConnectionCommand.self,
            InfoCommand.self,
            ProbeCommand.self,
            RelayCommand.self
        ]
    )

    public init() {}
}
