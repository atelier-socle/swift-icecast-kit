// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("IcecastError")
struct IcecastErrorTests {

    // MARK: - Non-empty Descriptions

    @Test("connectionFailed has non-empty description with context")
    func connectionFailedDescription() {
        let error = IcecastError.connectionFailed(host: "example.com", port: 8000, reason: "refused")
        #expect(!error.description.isEmpty)
        #expect(error.description.contains("example.com"))
        #expect(error.description.contains("8000"))
    }

    @Test("connectionTimeout has non-empty description with seconds")
    func connectionTimeoutDescription() {
        let error = IcecastError.connectionTimeout(seconds: 30.0)
        #expect(!error.description.isEmpty)
        #expect(error.description.contains("30"))
    }

    @Test("connectionLost has non-empty description")
    func connectionLostDescription() {
        let error = IcecastError.connectionLost(reason: "reset by peer")
        #expect(!error.description.isEmpty)
        #expect(error.description.contains("reset by peer"))
    }

    @Test("authenticationFailed has non-empty description with status code")
    func authenticationFailedDescription() {
        let error = IcecastError.authenticationFailed(statusCode: 401, message: "Unauthorized")
        #expect(!error.description.isEmpty)
        #expect(error.description.contains("401"))
    }

    @Test("protocolNegotiationFailed has non-empty description with tried protocols")
    func protocolNegotiationFailedDescription() {
        let error = IcecastError.protocolNegotiationFailed(tried: ["PUT", "SOURCE"])
        #expect(!error.description.isEmpty)
        #expect(error.description.contains("PUT"))
        #expect(error.description.contains("SOURCE"))
    }

    @Test("mountpointInUse has non-empty description with mountpoint")
    func mountpointInUseDescription() {
        let error = IcecastError.mountpointInUse("/live.mp3")
        #expect(!error.description.isEmpty)
        #expect(error.description.contains("/live.mp3"))
    }

    @Test("metadataTooLong has non-empty description with lengths")
    func metadataTooLongDescription() {
        let error = IcecastError.metadataTooLong(length: 500, maxLength: 256)
        #expect(!error.description.isEmpty)
        #expect(error.description.contains("500"))
        #expect(error.description.contains("256"))
    }

    @Test("invalidState has non-empty description with state names")
    func invalidStateDescription() {
        let error = IcecastError.invalidState(current: "idle", expected: "connected")
        #expect(!error.description.isEmpty)
        #expect(error.description.contains("idle"))
        #expect(error.description.contains("connected"))
    }

    @Test("notConnected has non-empty description")
    func notConnectedDescription() {
        let error = IcecastError.notConnected
        #expect(!error.description.isEmpty)
    }

    @Test("emptyResponse has non-empty description")
    func emptyResponseDescription() {
        let error = IcecastError.emptyResponse
        #expect(!error.description.isEmpty)
    }

    // MARK: - Hashable / Equatable

    @Test("Same error cases are equal")
    func sameCasesAreEqual() {
        let e1 = IcecastError.connectionFailed(host: "a", port: 1, reason: "r")
        let e2 = IcecastError.connectionFailed(host: "a", port: 1, reason: "r")
        #expect(e1 == e2)
    }

    @Test("Different error cases are not equal")
    func differentCasesAreNotEqual() {
        let e1 = IcecastError.notConnected
        let e2 = IcecastError.alreadyConnected
        #expect(e1 != e2)
    }

    @Test("Error cases with different values are not equal")
    func differentValuesAreNotEqual() {
        let e1 = IcecastError.connectionFailed(host: "a", port: 1, reason: "r")
        let e2 = IcecastError.connectionFailed(host: "b", port: 2, reason: "s")
        #expect(e1 != e2)
    }

    // MARK: - All Categories

    @Test("tlsError has non-empty description")
    func tlsErrorDescription() {
        let error = IcecastError.tlsError(reason: "certificate expired")
        #expect(error.description.contains("certificate expired"))
    }

    @Test("dnsResolutionFailed has non-empty description")
    func dnsResolutionFailedDescription() {
        let error = IcecastError.dnsResolutionFailed(host: "invalid.host")
        #expect(error.description.contains("invalid.host"))
    }

    @Test("credentialsRequired has non-empty description")
    func credentialsRequiredDescription() {
        let error = IcecastError.credentialsRequired
        #expect(!error.description.isEmpty)
    }

    @Test("serverError has description with status code")
    func serverErrorDescription() {
        let error = IcecastError.serverError(statusCode: 503, message: "Service Unavailable")
        #expect(error.description.contains("503"))
    }

    @Test("sendFailed has non-empty description")
    func sendFailedDescription() {
        let error = IcecastError.sendFailed(reason: "broken pipe")
        #expect(error.description.contains("broken pipe"))
    }

    @Test("invalidAudioData has non-empty description")
    func invalidAudioDataDescription() {
        let error = IcecastError.invalidAudioData(reason: "empty buffer")
        #expect(error.description.contains("empty buffer"))
    }

    @Test("adminAPIUnavailable has non-empty description")
    func adminAPIUnavailableDescription() {
        let error = IcecastError.adminAPIUnavailable
        #expect(!error.description.isEmpty)
    }
}
