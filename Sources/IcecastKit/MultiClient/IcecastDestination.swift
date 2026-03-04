// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Snapshot of a single destination in a multi-destination setup.
///
/// Returned by ``MultiIcecastClient/destinations`` to provide
/// a read-only view of each destination's current state.
public struct IcecastDestination: Sendable {

    /// The unique label identifying this destination.
    public let label: String

    /// The server configuration for this destination.
    public let configuration: IcecastConfiguration

    /// The current connection state.
    public let state: ConnectionState

    /// The connection statistics, or `nil` if never connected.
    public let statistics: ConnectionStatistics?

    /// Creates a destination snapshot.
    ///
    /// - Parameters:
    ///   - label: The destination label.
    ///   - configuration: The server configuration.
    ///   - state: The current connection state.
    ///   - statistics: The connection statistics.
    public init(
        label: String,
        configuration: IcecastConfiguration,
        state: ConnectionState,
        statistics: ConnectionStatistics?
    ) {
        self.label = label
        self.configuration = configuration
        self.state = state
        self.statistics = statistics
    }
}
