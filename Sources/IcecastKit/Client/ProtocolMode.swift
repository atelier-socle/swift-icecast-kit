// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// The streaming protocol variant to use when connecting to a server.
///
/// Use ``auto`` to let IcecastKit negotiate the best protocol automatically.
public enum ProtocolMode: Sendable, Hashable, Codable {

    /// Automatically detect and negotiate the best protocol.
    case auto

    /// Icecast HTTP PUT (modern, Icecast 2.4+).
    case icecastPUT

    /// Icecast SOURCE (legacy, pre-2.4.0).
    case icecastSOURCE

    /// SHOUTcast v1 protocol.
    case shoutcastV1

    /// SHOUTcast v2 protocol with a specific stream ID.
    case shoutcastV2(streamId: Int)
}
