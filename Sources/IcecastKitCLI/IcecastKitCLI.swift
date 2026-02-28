// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import IcecastKitCommands

/// Entry point for the icecast-cli command-line tool.
@main
struct IcecastKitCLI {
    static func main() async throws {
        await IcecastKitCommand.main()
    }
}
