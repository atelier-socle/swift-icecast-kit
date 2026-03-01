// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Parses Icecast admin API XML responses into structured stats models.
///
/// Uses Foundation's `XMLParser` (SAX-based) to extract server and
/// mountpoint statistics from the Icecast admin XML format.
final class IcecastXMLParser: NSObject, XMLParserDelegate {

    private var serverVersion: String = ""
    private var mountpoints: [MountStatsBuilder] = []
    private var currentMount: MountStatsBuilder?
    private var currentElement: String = ""
    private var currentText: String = ""

    /// Parses XML data into ``ServerStats``.
    ///
    /// - Parameter data: The XML response body.
    /// - Returns: The parsed server statistics.
    /// - Throws: ``IcecastError/invalidResponse(reason:)`` if parsing fails.
    func parseServerStats(from data: Data) throws -> ServerStats {
        try performParse(data)

        var totalListeners = 0
        var mountpointPaths: [String] = []

        for mount in mountpoints {
            mountpointPaths.append(mount.mountpoint)
            totalListeners += mount.listeners
        }

        return ServerStats(
            serverVersion: serverVersion,
            activeMountpoints: mountpointPaths,
            totalListeners: totalListeners,
            totalSources: mountpoints.count
        )
    }

    /// Parses XML data into ``MountStats`` for a specific mountpoint.
    ///
    /// - Parameters:
    ///   - data: The XML response body.
    ///   - mountpoint: The mountpoint to extract stats for.
    /// - Returns: The parsed mountpoint statistics.
    /// - Throws: ``IcecastError/mountpointNotFound(_:)`` if the mountpoint
    ///   is not in the response.
    func parseMountStats(from data: Data, mountpoint: String) throws -> MountStats {
        try performParse(data)

        guard let mount = mountpoints.first(where: { $0.mountpoint == mountpoint }) else {
            throw IcecastError.mountpointNotFound(mountpoint)
        }

        return mount.toMountStats()
    }

    // MARK: - Private

    private func performParse(_ data: Data) throws {
        serverVersion = ""
        mountpoints = []
        currentMount = nil
        currentElement = ""
        currentText = ""

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw IcecastError.invalidResponse(
                reason: "XML parsing failed: \(parser.parserError?.localizedDescription ?? "unknown")"
            )
        }
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        currentElement = elementName
        currentText = ""

        if elementName == "source", let mount = attributes["mount"] {
            currentMount = MountStatsBuilder(mountpoint: mount)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if elementName == "source" {
            if let mount = currentMount {
                mountpoints.append(mount)
            }
            currentMount = nil
        } else if currentMount != nil {
            applyMountField(elementName, value: trimmed)
        } else if elementName == "server_id" {
            serverVersion = trimmed
        }

        currentElement = ""
        currentText = ""
    }

    private func applyMountField(_ field: String, value: String) {
        switch field {
        case "listeners":
            currentMount?.listeners = Int(value) ?? 0
        case "title":
            currentMount?.title = value.isEmpty ? nil : value
        case "bitrate":
            currentMount?.bitrate = Int(value)
        case "genre":
            currentMount?.genre = value.isEmpty ? nil : value
        case "server_type":
            currentMount?.serverType = value.isEmpty ? nil : value
        case "connected":
            currentMount?.connected = Double(value)
        default:
            break
        }
    }
}

/// Internal builder for accumulating mountpoint stats during XML parsing.
private struct MountStatsBuilder {
    var mountpoint: String
    var listeners: Int = 0
    var title: String?
    var bitrate: Int?
    var genre: String?
    var serverType: String?
    var connected: Double?

    func toMountStats() -> MountStats {
        MountStats(
            mountpoint: mountpoint,
            listeners: listeners,
            streamTitle: title,
            bitrate: bitrate,
            genre: genre,
            contentType: serverType,
            connectedDuration: connected
        )
    }
}
