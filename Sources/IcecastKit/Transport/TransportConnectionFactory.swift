// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Factory for creating platform-appropriate transport connections.
///
/// Returns ``NWTransportConnection`` on Apple platforms (using Network.framework)
/// and ``POSIXTransportConnection`` on Linux (using POSIX sockets).
public enum TransportConnectionFactory {

    /// Creates a new transport connection appropriate for the current platform.
    ///
    /// - Returns: A ``TransportConnection`` instance.
    public static func makeConnection() -> any TransportConnection {
        #if canImport(Network)
            return NWTransportConnection()
        #else
            return POSIXTransportConnection()
        #endif
    }
}
