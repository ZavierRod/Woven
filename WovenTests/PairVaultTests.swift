import CryptoKit
import Foundation
import Testing
@testable import Woven

@MainActor
struct PairVaultCryptographyTests {
    private let cryptography = PairVaultCryptography()

    @Test
    func twoSharesAreRequiredAndReconstructExactly() throws {
        let vaultKey = try cryptography.generateVaultKey()
        let shares = try cryptography.split(vaultKey)

        #expect(shares.local.count == 32)
        #expect(shares.partner.count == 32)
        #expect(shares.local != vaultKey)
        #expect(shares.partner != vaultKey)
        #expect(try cryptography.combine(shares.local, shares.partner) == vaultKey)

        let unrelatedShare = try cryptography.generateVaultKey()
        let incorrectKey = try cryptography.combine(shares.local, unrelatedShare)
        #expect(incorrectKey != vaultKey)

        let aad = try cryptography.mediaAAD(
            vaultID: "share-test-vault",
            mediaID: "share-test-media",
            membershipVersion: 1,
            purpose: "media-blob"
        )
        let ciphertext = try cryptography.seal(
            Data("two-shares-required".utf8),
            vaultKey: vaultKey,
            authenticatedData: aad
        )
        #expect(throws: (any Error).self) {
            try cryptography.open(ciphertext, vaultKey: incorrectKey, authenticatedData: aad)
        }
    }

    @Test
    func curve25519EnvelopeRoundTripRejectsWrongRecipientSenderAndContext() throws {
        let senderPrivate = cryptography.generateIdentityPrivateKey()
        let senderPublic = try cryptography.publicKey(for: senderPrivate)
        let recipientPrivate = cryptography.generateIdentityPrivateKey()
        let recipientPublic = try cryptography.publicKey(for: recipientPrivate)
        let wrongRecipient = cryptography.generateIdentityPrivateKey()
        let share = try cryptography.generateVaultKey()
        let context = accessContext(vault: "vault-a", request: "request-a")
        let envelope = try cryptography.sealShare(
            share,
            recipientPublicKey: recipientPublic,
            context: context,
            senderPrivateKey: senderPrivate
        )

        #expect(try cryptography.openShare(
            envelope,
            recipientPrivateKey: recipientPrivate,
            context: context,
            expectedSenderPublicKey: senderPublic
        ) == share)
        #expect(!envelope.contains(share.base64EncodedString()))

        #expect(throws: (any Error).self) {
            try cryptography.openShare(
                envelope,
                recipientPrivateKey: wrongRecipient,
                context: context,
                expectedSenderPublicKey: senderPublic
            )
        }
        #expect(throws: PairVaultError.contextMismatch) {
            try cryptography.openShare(
                envelope,
                recipientPrivateKey: recipientPrivate,
                context: context,
                expectedSenderPublicKey: try cryptography.generateVaultKey()
            )
        }
        #expect(throws: (any Error).self) {
            try cryptography.openShare(
                envelope,
                recipientPrivateKey: recipientPrivate,
                context: accessContext(vault: "vault-b", request: "request-a"),
                expectedSenderPublicKey: senderPublic
            )
        }
        #expect(throws: (any Error).self) {
            try cryptography.openShare(
                envelope,
                recipientPrivateKey: recipientPrivate,
                context: accessContext(vault: "vault-a", request: "request-b"),
                expectedSenderPublicKey: senderPublic
            )
        }
    }

    @Test
    func envelopeAndMediaTamperingAreDetectedAndNoncesAreFresh() throws {
        let recipientPrivate = cryptography.generateIdentityPrivateKey()
        let recipientPublic = try cryptography.publicKey(for: recipientPrivate)
        let share = try cryptography.generateVaultKey()
        let context = accessContext(vault: "vault", request: "request")
        let first = try cryptography.sealShare(share, recipientPublicKey: recipientPublic, context: context)
        let second = try cryptography.sealShare(share, recipientPublicKey: recipientPublic, context: context)
        #expect(first != second)

        let tamperedEnvelope = try mutateEnvelope(first)
        #expect(throws: (any Error).self) {
            try cryptography.openShare(tamperedEnvelope, recipientPrivateKey: recipientPrivate, context: context)
        }

        let key = try cryptography.generateVaultKey()
        let plaintext = Data([0xff, 0xd8, 0xff, 0xe0]) + Data("recognizable-private-image".utf8)
        let aad = try cryptography.mediaAAD(
            vaultID: "vault",
            mediaID: "media",
            membershipVersion: 1,
            purpose: "media-blob"
        )
        let sealed = try cryptography.seal(plaintext, vaultKey: key, authenticatedData: aad)
        #expect(sealed.range(of: plaintext) == nil)
        #expect(try cryptography.open(sealed, vaultKey: key, authenticatedData: aad) == plaintext)

        var tampered = sealed
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        #expect(throws: (any Error).self) {
            try cryptography.open(tampered, vaultKey: key, authenticatedData: aad)
        }
        #expect(throws: (any Error).self) {
            try cryptography.open(
                sealed,
                vaultKey: key,
                authenticatedData: try cryptography.mediaAAD(
                    vaultID: "vault",
                    mediaID: "other-media",
                    membershipVersion: 1,
                    purpose: "media-blob"
                )
            )
        }
        #expect(throws: (any Error).self) {
            try cryptography.open(
                sealed,
                vaultKey: key,
                authenticatedData: try cryptography.mediaAAD(
                    vaultID: "other-vault",
                    mediaID: "media",
                    membershipVersion: 1,
                    purpose: "media-blob"
                )
            )
        }
        #expect(throws: (any Error).self) {
            try cryptography.open(
                sealed,
                vaultKey: key,
                authenticatedData: try cryptography.mediaAAD(
                    vaultID: "vault",
                    mediaID: "media",
                    membershipVersion: 2,
                    purpose: "media-blob"
                )
            )
        }


        let metadataAAD = try cryptography.mediaAAD(
            vaultID: "vault",
            mediaID: "media",
            membershipVersion: 1,
            purpose: "media-metadata"
        )
        var sealedMetadata = try cryptography.seal(
            Data("private-filename.jpg".utf8),
            vaultKey: key,
            authenticatedData: metadataAAD
        )
        sealedMetadata[sealedMetadata.index(before: sealedMetadata.endIndex)] ^= 0x01
        #expect(throws: (any Error).self) {
            try cryptography.open(sealedMetadata, vaultKey: key, authenticatedData: metadataAAD)
        }
    }

    private func accessContext(vault: String, request: String) -> PairAccessContext {
        PairAccessContext(
            protocolName: "woven-pair-v2",
            purpose: "access-share",
            vaultID: vault,
            requestID: request,
            membershipVersion: 1,
            requesterAccountID: 1,
            requesterDeviceID: "device-a",
            requesterEphemeralPublicKey: Data(repeating: 4, count: 32).base64EncodedString(),
            approverAccountID: 2,
            approverDeviceID: "device-b",
            createdAtMS: 1_700_000_000_000,
            expiresAtMS: 1_700_000_060_000
        )
    }

    private func mutateEnvelope(_ encoded: String) throws -> String {
        let data = try #require(Data(base64Encoded: encoded))
        var envelope = try JSONDecoder().decode(PairSealedEnvelope.self, from: data)
        var sealed = try #require(Data(base64Encoded: envelope.sealedBox))
        sealed[sealed.index(before: sealed.endIndex)] ^= 0x01
        envelope = PairSealedEnvelope(
            version: envelope.version,
            senderPublicKey: envelope.senderPublicKey,
            sealedBox: sealed.base64EncodedString()
        )
        return try JSONEncoder.pairCanonical.encode(envelope).base64EncodedString()
    }
}

@MainActor
struct PairVaultTwoClientStateTests {
    @Test
    func twoClientsInviteApprovePersistLockRelaunchAndDelete() async throws {
        let relay = EnforcingPairRelay()
        let aliceSecrets = InMemoryPairSecrets()
        let bobSecrets = InMemoryPairSecrets()
        let authentication = AuthenticationRecorder()
        let alice = PairVaultStore(
            dependencies: dependencies(relay: relay, secrets: aliceSecrets) { _ in
                await authentication.record()
            }
        )
        let bob = PairVaultStore(
            dependencies: dependencies(relay: relay, secrets: bobSecrets) { _ in
                await authentication.record()
            }
        )

        await bob.signIn(session: session(for: 2))
        #expect(bob.phase == .ready)
        await alice.signIn(session: session(for: 1))
        #expect(alice.phase == .ready)

        await alice.createVault(named: "Two-person memories", partnerInviteCode: "DEV2")
        let token = try #require(alice.invitationToken)
        guard case .waitingForPartner(let createdVault) = alice.phase else {
            Issue.record("Creator did not enter the invitation wait state")
            return
        }
        let vaultID = createdVault.vaultID

        try await bob.refresh()
        guard case .invitation = bob.phase else {
            Issue.record("Partner did not receive the targeted invitation")
            return
        }
        await bob.acceptInvitation(token: token)
        guard case .locked = bob.phase else {
            Issue.record("Accepted Pair vault was not locked")
            return
        }
        #expect(bob.decryptedMedia.isEmpty)
        let aliceShare = try aliceSecrets.share(vaultID: vaultID, accountID: 1)
        let bobShare = try bobSecrets.share(vaultID: vaultID, accountID: 2)
        #expect(relay.serializedStorage().contains(aliceShare.base64EncodedString()) == false)
        #expect(relay.serializedStorage().contains(bobShare.base64EncodedString()) == false)

        try await alice.refresh()
        guard case .locked = alice.phase else {
            Issue.record("Creator did not observe active membership")
            return
        }
        #expect(alice.decryptedMedia.isEmpty)

        await alice.requestAccess()
        guard case .awaitingApproval = alice.accessPhase else {
            Issue.record("Requester did not enter awaiting-approval state")
            return
        }
        await bob.pollOnce()
        let request = try #require(bob.incomingRequests.first)
        await bob.approve(request)
        #expect(await authentication.count == 1)
        #expect(bob.decryptedMedia.isEmpty)
        guard case .locked = bob.phase else {
            Issue.record("Approver reconstructed the vault key")
            return
        }

        await alice.pollOnce()
        guard case .unlocked(_, let name) = alice.phase else {
            Issue.record("Requester did not unlock after consuming approval")
            return
        }
        #expect(name == "Two-person memories")

        let photo = Data("pair-photo-plaintext-only-in-memory".utf8)
        await alice.importPhoto(photo)
        #expect(alice.decryptedMedia.first?.imageData == photo)
        #expect(relay.serializedStorage().contains("pair-photo-plaintext-only-in-memory") == false)

        alice.lock()
        #expect(alice.decryptedMedia.isEmpty)
        guard case .locked = alice.phase else {
            Issue.record("Lock did not remove decrypted presentation")
            return
        }

        // Exercise the inverse direction: Bob requests and Alice authenticates
        // before releasing only Alice's local share to Bob's ephemeral key.
        await bob.requestAccess()
        guard case .awaitingApproval = bob.accessPhase else {
            Issue.record("Second member did not enter awaiting-approval state")
            return
        }
        await alice.pollOnce()
        let bobRequest = try #require(alice.incomingRequests.first)
        await alice.approve(bobRequest)
        #expect(await authentication.count == 2)
        await bob.pollOnce()
        #expect(Set(relay.requestEphemeralPublicKeys).count == relay.requestEphemeralPublicKeys.count)
        #expect(bob.decryptedMedia.first?.imageData == photo)
        let bobPhoto = Data("second-member-photo-plaintext-only-in-memory".utf8)
        await bob.importPhoto(bobPhoto)
        #expect(bob.decryptedMedia.contains(where: { $0.imageData == bobPhoto }))
        #expect(relay.serializedStorage().contains("second-member-photo-plaintext-only-in-memory") == false)
        bob.logout()
        #expect(bob.decryptedMedia.isEmpty)
        #expect(bob.phase == .signedOut)
        await bob.signIn(session: session(for: 2))
        guard case .locked = bob.phase else {
            Issue.record("Second member did not relock after logout and sign-in")
            return
        }

        let relaunchedAlice = PairVaultStore(
            dependencies: dependencies(
                relay: relay,
                secrets: aliceSecrets,
                lockTimeout: .seconds(2)
            ) { _ in await authentication.record() }
        )
        await relaunchedAlice.signIn(session: session(for: 1))
        guard case .locked = relaunchedAlice.phase else {
            Issue.record("Relaunched Pair vault was not locked")
            return
        }
        await relaunchedAlice.requestAccess()
        await bob.pollOnce()
        let secondRequest = try #require(bob.incomingRequests.first)
        await bob.approve(secondRequest)
        #expect(await authentication.count == 3)
        await relaunchedAlice.pollOnce()
        #expect(Set(relaunchedAlice.decryptedMedia.map(\.imageData)) == Set([photo, bobPhoto]))

        let mediaIDs = relaunchedAlice.decryptedMedia.map(\.id)
        for mediaID in mediaIDs {
            await relaunchedAlice.deleteMedia(id: mediaID)
        }
        #expect(relaunchedAlice.decryptedMedia.isEmpty)
        #expect(relay.mediaCount == 0)

        try await Task.sleep(for: .milliseconds(2_100))
        guard case .locked = relaunchedAlice.phase else {
            Issue.record("Pair vault did not lock after its inactivity timeout")
            return
        }
        #expect(relaunchedAlice.decryptedMedia.isEmpty)

        // A remotely revoked member must lose any reconstructed key and its
        // persisted local share on the next membership update.
        await bob.requestAccess()
        await relaunchedAlice.pollOnce()
        let revocationRequest = try #require(relaunchedAlice.incomingRequests.first)
        await relaunchedAlice.approve(revocationRequest)
        #expect(await authentication.count == 4)
        await bob.pollOnce()
        guard case .unlocked = bob.phase else {
            Issue.record("Second member did not unlock before revocation test")
            return
        }
        await relaunchedAlice.revokePartner()
        await bob.pollOnce()
        #expect(bob.phase == .ready)
        #expect(bob.decryptedMedia.isEmpty)
        #expect(throws: PairVaultError.missingLocalShare) {
            try bobSecrets.share(vaultID: vaultID, accountID: 2)
        }
    }

    @Test
    func tamperedConsumedApprovalFailsClosedWithoutUnlocking() async throws {
        let relay = EnforcingPairRelay()
        let alice = PairVaultStore(dependencies: dependencies(relay: relay, secrets: InMemoryPairSecrets()))
        let bob = PairVaultStore(dependencies: dependencies(relay: relay, secrets: InMemoryPairSecrets()))

        await bob.signIn(session: session(for: 2))
        await alice.signIn(session: session(for: 1))
        await alice.createVault(named: "Tamper test", partnerInviteCode: "DEV2")
        let token = try #require(alice.invitationToken)
        try await bob.refresh()
        await bob.acceptInvitation(token: token)
        try await alice.refresh()

        await alice.requestAccess()
        await bob.pollOnce()
        let request = try #require(bob.incomingRequests.first)
        await bob.approve(request)
        relay.tamperNextConsumedEnvelope = true
        await alice.pollOnce()

        guard case .failed = alice.accessPhase else {
            Issue.record("Tampered approval did not enter the failure state")
            return
        }
        guard case .locked = alice.phase else {
            Issue.record("Tampered approval unlocked the Pair vault")
            return
        }
        #expect(alice.decryptedMedia.isEmpty)
    }

    private func dependencies(
        relay: EnforcingPairRelay,
        secrets: InMemoryPairSecrets,
        lockTimeout: Duration = .seconds(300),
        authenticate: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) -> PairVaultDependencies {
        PairVaultDependencies(
            api: relay,
            secrets: secrets,
            cryptography: PairVaultCryptography(),
            updates: PairDevelopmentPollingTransport(),
            lockTimeout: lockTimeout,
            authenticate: authenticate
        )
    }

    private func session(for id: Int) -> PairSession {
        PairSession(
            accessToken: "test-token-\(id)",
            tokenType: "bearer",
            userID: id,
            username: id == 1 ? "alice" : "bob",
            email: "user-\(id)@example.invalid",
            fullName: nil,
            inviteCode: "DEV\(id)"
        )
    }
}

private actor AuthenticationRecorder {
    private(set) var count = 0
    func record() { count += 1 }
}

private final class InMemoryPairSecrets: PairSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var identities: [Int: Data] = [:]
    private var signingKeys: [Int: Data] = [:]
    private var shares: [String: Data] = [:]
    private var tokens: [String: String] = [:]

    func identityPrivateKey(accountID: Int, cryptography: PairVaultCryptography) throws -> Data {
        lock.withLock {
            if let existing = identities[accountID] { return existing }
            let created = cryptography.generateIdentityPrivateKey()
            identities[accountID] = created
            return created
        }
    }

    func signingPrivateKey(accountID: Int, cryptography: PairVaultCryptography) throws -> Data {
        lock.withLock {
            if let existing = signingKeys[accountID] { return existing }
            let created = cryptography.generateSigningPrivateKey()
            signingKeys[accountID] = created
            return created
        }
    }

    func saveShare(_ share: Data, vaultID: String, accountID: Int) throws {
        lock.withLock { shares["\(accountID)|\(vaultID)"] = share }
    }

    func share(vaultID: String, accountID: Int) throws -> Data {
        try lock.withLock {
            guard let share = shares["\(accountID)|\(vaultID)"] else { throw PairVaultError.missingLocalShare }
            return share
        }
    }

    func deleteShare(vaultID: String, accountID: Int) {
        lock.withLock { shares["\(accountID)|\(vaultID)"] = nil }
    }

    func saveInvitationToken(_ token: String, vaultID: String, accountID: Int) throws {
        lock.withLock { tokens["\(accountID)|\(vaultID)"] = token }
    }

    func invitationToken(vaultID: String, accountID: Int) throws -> String? {
        lock.withLock { tokens["\(accountID)|\(vaultID)"] }
    }

    func deleteInvitationToken(vaultID: String, accountID: Int) {
        lock.withLock { tokens["\(accountID)|\(vaultID)"] = nil }
    }
}

@MainActor
private final class EnforcingPairRelay: PairRelayAPI, @unchecked Sendable {
    private let cryptography = PairVaultCryptography()
    private var devices: [Int: PairDevice] = [:]
    private var vault: PairVaultRecord?
    private var invitation: PairInvitationRecord?
    private var invitationTarget = 0
    private var invitationTokenHash = ""
    private var requests: [String: PairAccessRecord] = [:]
    private var media: [String: PairMediaRecord] = [:]
    var tamperNextConsumedEnvelope = false

    var mediaCount: Int { media.count }
    var requestEphemeralPublicKeys: [String] {
        requests.values.map(\.context.requesterEphemeralPublicKey)
    }

    func account(inviteCode: String, session: PairSession) async throws -> PairAccountLookup {
        guard inviteCode == "DEV1" || inviteCode == "DEV2" else {
            throw PairVaultError.relay("Unknown test invite code")
        }
        let id = inviteCode == "DEV1" ? 1 : 2
        return PairAccountLookup(userID: id, username: id == 1 ? "alice" : "bob")
    }

    #if WOVEN_DEVELOPMENT_AUTH
    func developmentSession(_ account: PairDevelopmentAccount) async throws -> PairSession {
        let id = account == .alice ? 1 : 2
        return PairSession(
            accessToken: "token-\(id)",
            tokenType: "bearer",
            userID: id,
            username: account.rawValue,
            email: "\(account.rawValue)@example.com",
            fullName: account.displayName,
            inviteCode: "DEV\(id)"
        )
    }
    #endif

    func registerDevice(
        session: PairSession,
        deviceID: String,
        agreementPublicKey: Data,
        signingPublicKey: Data
    ) async throws -> PairDevice {
        if let existing = devices[session.userID] {
            guard existing.deviceID == deviceID,
                  existing.agreementPublicKey == agreementPublicKey.base64EncodedString(),
                  existing.signingPublicKey == signingPublicKey.base64EncodedString() else {
                throw PairVaultError.relay("Device replacement rejected")
            }
            return existing
        }
        let record = PairDevice(
            deviceID: deviceID,
            userID: session.userID,
            agreementPublicKey: agreementPublicKey.base64EncodedString(),
            signingPublicKey: signingPublicKey.base64EncodedString(),
            createdAtMS: nowMS,
            revoked: false
        )
        devices[session.userID] = record
        return record
    }

    func device(for userID: Int, session: PairSession) async throws -> PairDevice {
        guard let device = devices[userID] else { throw PairVaultError.relay("Partner device is not registered") }
        return device
    }

    func createVault(
        session: PairSession,
        vaultID: String,
        creatorDeviceID: String,
        encryptedMetadata: String,
        invitationID: String,
        target: PairDevice,
        tokenHash: String,
        encryptedShareEnvelope: String,
        createdAtMS: Int64,
        expiresAtMS: Int64
    ) async throws -> PairVaultCreateResponse {
        guard vault == nil, session.userID != target.userID else { throw PairVaultError.relay("Invalid membership") }
        let member = PairMember(userID: session.userID, deviceID: creatorDeviceID, role: "creator", status: "active")
        let created = PairVaultRecord(
            vaultID: vaultID,
            encryptedMetadata: encryptedMetadata,
            membershipVersion: 1,
            status: "pending",
            createdAtMS: createdAtMS,
            members: [member]
        )
        let context = PairInvitationContext(
            protocolName: "woven-pair-v2",
            purpose: "invitation-share",
            vaultID: vaultID,
            invitationID: invitationID,
            membershipVersion: 1,
            creatorAccountID: session.userID,
            creatorDeviceID: creatorDeviceID,
            targetAccountID: target.userID,
            targetDeviceID: target.deviceID,
            createdAtMS: createdAtMS,
            expiresAtMS: expiresAtMS
        )
        let invite = PairInvitationRecord(
            invitationID: invitationID,
            vaultID: vaultID,
            status: "pending",
            context: context,
            encryptedShareEnvelope: encryptedShareEnvelope
        )
        vault = created
        invitation = invite
        invitationTarget = target.userID
        invitationTokenHash = tokenHash
        return PairVaultCreateResponse(vault: created, invitation: invite)
    }

    func invitations(session: PairSession) async throws -> [PairInvitationRecord] {
        guard session.userID == invitationTarget, let invitation, invitation.status == "pending" else { return [] }
        return [invitation]
    }

    func acceptInvitation(id: String, token: String, session: PairSession) async throws -> PairInvitationAcceptResponse {
        guard session.userID == invitationTarget,
              var invitation,
              invitation.invitationID == id,
              invitation.status == "pending",
              cryptography.sha256Hex(token) == invitationTokenHash,
              var vault,
              let device = devices[session.userID] else {
            throw PairVaultError.relay("Invitation rejected")
        }
        invitation = PairInvitationRecord(
            invitationID: invitation.invitationID,
            vaultID: invitation.vaultID,
            status: "accepted",
            context: invitation.context,
            encryptedShareEnvelope: invitation.encryptedShareEnvelope
        )
        vault = PairVaultRecord(
            vaultID: vault.vaultID,
            encryptedMetadata: vault.encryptedMetadata,
            membershipVersion: vault.membershipVersion,
            status: "active",
            createdAtMS: vault.createdAtMS,
            members: vault.members + [PairMember(userID: session.userID, deviceID: device.deviceID, role: "partner", status: "active")]
        )
        self.invitation = invitation
        self.vault = vault
        return PairInvitationAcceptResponse(vault: vault, invitation: invitation)
    }

    func vaults(session: PairSession) async throws -> [PairVaultRecord] {
        guard let vault, vault.members.contains(where: { $0.userID == session.userID }) else { return [] }
        return [vault]
    }

    func createAccessRequest(
        vaultID: String,
        requestID: String,
        requesterDeviceID: String,
        ephemeralPublicKey: Data,
        createdAtMS: Int64,
        expiresAtMS: Int64,
        session: PairSession
    ) async throws -> PairAccessRecord {
        guard let vault, vault.status == "active",
              vault.vaultID == vaultID,
              let requester = vault.members.first(where: { $0.userID == session.userID && $0.deviceID == requesterDeviceID }),
              let approver = vault.members.first(where: { $0.userID != requester.userID }),
              requests.values.allSatisfy({ $0.status != .pending && $0.status != .approved }) else {
            throw PairVaultError.relay("Access request rejected")
        }
        let context = PairAccessContext(
            protocolName: "woven-pair-v2",
            purpose: "access-share",
            vaultID: vaultID,
            requestID: requestID,
            membershipVersion: vault.membershipVersion,
            requesterAccountID: session.userID,
            requesterDeviceID: requesterDeviceID,
            requesterEphemeralPublicKey: ephemeralPublicKey.base64EncodedString(),
            approverAccountID: approver.userID,
            approverDeviceID: approver.deviceID,
            createdAtMS: createdAtMS,
            expiresAtMS: expiresAtMS
        )
        let request = PairAccessRecord(
            requestID: requestID,
            vaultID: vaultID,
            status: .pending,
            context: context,
            encryptedShareEnvelope: nil
        )
        requests[requestID] = request
        return request
    }

    func incomingAccessRequests(session: PairSession) async throws -> [PairAccessRecord] {
        requests.values.filter { $0.context.approverAccountID == session.userID && $0.status == .pending }
    }

    func accessRequest(id: String, session: PairSession) async throws -> PairAccessRecord {
        guard let request = requests[id],
              [request.context.requesterAccountID, request.context.approverAccountID].contains(session.userID) else {
            throw PairVaultError.relay("Request not found")
        }
        return PairAccessRecord(
            requestID: request.requestID,
            vaultID: request.vaultID,
            status: request.status,
            context: request.context,
            encryptedShareEnvelope: nil
        )
    }

    func approveAccessRequest(id: String, envelope: String, session: PairSession) async throws -> PairAccessRecord {
        guard let request = requests[id], request.status == .pending,
              request.context.approverAccountID == session.userID else {
            throw PairVaultError.relay("Approval rejected")
        }
        let approved = PairAccessRecord(
            requestID: request.requestID,
            vaultID: request.vaultID,
            status: .approved,
            context: request.context,
            encryptedShareEnvelope: envelope
        )
        requests[id] = approved
        return approved
    }

    func denyAccessRequest(id: String, session: PairSession) async throws {
        guard let request = requests[id], request.status == .pending,
              request.context.approverAccountID == session.userID else { throw PairVaultError.relay("Denial rejected") }
        requests[id] = PairAccessRecord(
            requestID: request.requestID,
            vaultID: request.vaultID,
            status: .denied,
            context: request.context,
            encryptedShareEnvelope: nil
        )
    }

    func consumeAccessRequest(id: String, session: PairSession) async throws -> PairConsumeResponse {
        guard let request = requests[id], request.status == .approved,
              request.context.requesterAccountID == session.userID,
              let envelope = request.encryptedShareEnvelope else {
            throw PairVaultError.relay("Approval cannot be replayed")
        }
        requests[id] = PairAccessRecord(
            requestID: request.requestID,
            vaultID: request.vaultID,
            status: .consumed,
            context: request.context,
            encryptedShareEnvelope: nil
        )
        var returnedEnvelope = envelope
        if tamperNextConsumedEnvelope, var bytes = Data(base64Encoded: envelope), !bytes.isEmpty {
            bytes[bytes.index(before: bytes.endIndex)] ^= 0x01
            returnedEnvelope = bytes.base64EncodedString()
            tamperNextConsumedEnvelope = false
        }
        return PairConsumeResponse(
            status: "consumed",
            context: request.context,
            encryptedShareEnvelope: returnedEnvelope
        )
    }

    func cancelAccessRequest(id: String, session: PairSession) async throws {
        guard let request = requests[id], request.context.requesterAccountID == session.userID else { return }
        requests[id] = PairAccessRecord(
            requestID: request.requestID,
            vaultID: request.vaultID,
            status: .cancelled,
            context: request.context,
            encryptedShareEnvelope: nil
        )
    }

    func listMedia(vaultID: String, session: PairSession) async throws -> [PairMediaRecord] {
        media.values.map {
            PairMediaRecord(
                mediaID: $0.mediaID,
                vaultID: $0.vaultID,
                encryptedBlob: nil,
                encryptedMetadata: $0.encryptedMetadata,
                createdAtMS: $0.createdAtMS
            )
        }
    }

    func downloadMedia(vaultID: String, mediaID: String, session: PairSession) async throws -> PairMediaRecord {
        guard let record = media[mediaID] else { throw PairVaultError.relay("Media not found") }
        return record
    }

    func uploadMedia(
        vaultID: String,
        mediaID: String,
        encryptedBlob: Data,
        encryptedMetadata: Data,
        createdAtMS: Int64,
        session: PairSession
    ) async throws -> PairMediaRecord {
        let record = PairMediaRecord(
            mediaID: mediaID,
            vaultID: vaultID,
            encryptedBlob: encryptedBlob.base64EncodedString(),
            encryptedMetadata: encryptedMetadata.base64EncodedString(),
            createdAtMS: createdAtMS
        )
        media[mediaID] = record
        return record
    }

    func deleteMedia(vaultID: String, mediaID: String, session: PairSession) async throws {
        media[mediaID] = nil
    }

    func revokeMember(vaultID: String, userID: Int, session: PairSession) async throws {
        guard let vault else { return }
        self.vault = PairVaultRecord(
            vaultID: vault.vaultID,
            encryptedMetadata: vault.encryptedMetadata,
            membershipVersion: vault.membershipVersion + 1,
            status: "revoked",
            createdAtMS: vault.createdAtMS,
            members: vault.members.filter { $0.userID != userID }
        )
        requests = requests.mapValues {
            PairAccessRecord(
                requestID: $0.requestID,
                vaultID: $0.vaultID,
                status: .cancelled,
                context: $0.context,
                encryptedShareEnvelope: nil
            )
        }
    }

    func serializedStorage() -> String {
        String(describing: vault) + String(describing: invitation) + String(describing: media)
    }

    private var nowMS: Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
}
