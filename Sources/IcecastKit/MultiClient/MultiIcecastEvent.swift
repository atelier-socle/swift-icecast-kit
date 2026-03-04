// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Events emitted by ``MultiIcecastClient``.
///
/// Each event is tagged with the destination label so consumers
/// can identify which server is affected.
public enum MultiIcecastEvent: Sendable {

    /// A destination successfully connected to its server.
    case destinationConnected(label: String, serverVersion: String?)

    /// A destination disconnected from its server.
    case destinationDisconnected(label: String, error: IcecastError?)

    /// A destination is attempting to reconnect.
    case destinationReconnecting(label: String, attempt: Int)

    /// A destination successfully reconnected.
    case destinationReconnected(label: String)

    /// All registered destinations are now connected.
    case allConnected

    /// A multi-destination send completed with success/failure counts.
    case sendComplete(successCount: Int, failureCount: Int)

    /// A destination was added to the client.
    case destinationAdded(label: String)

    /// A destination was removed from the client.
    case destinationRemoved(label: String)

    /// Metadata was updated on a destination.
    case metadataUpdated(label: String)
}
