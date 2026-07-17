import CryptoKit
import Foundation
import LocalAuthentication
import Observation

struct PairVaultDependencies: Sendable {
    let api: any PairRelayAPI
    let secrets: any PairSecretStore
    let cryptography: PairVaultCryptography
    let updates: any PairVaultUpdateTransport
    let lockTimeout: Duration
    let authenticate: @Sendable (String) async throws -> Void

    static func live() -> Self {
        Self(
            api: PairVaultAPIClient(),
            secrets: PairVaultKeychain(),
            cryptography: PairVaultCryptography(),
            updates: PairDevelopmentPollingTransport(),
            lockTimeout: .seconds(300),
            authenticate: { reason in
                try await PairDeviceAuthentication.authenticate(reason: reason)
            }
        )
    }
}

enum PairDeviceAuthentication {
    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            throw evaluationError ?? PairVaultError.authenticationFailed
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
            throw PairVaultError.authenticationFailed
        }
    }
}

@Observable
@MainActor
final class PairVaultStore {
    private(set) var phase: PairVaultScreenPhase = .signedOut
    private(set) var accessPhase: PairAccessPhase = .none
    private(set) var incomingRequests: [PairAccessRecord] = []
    private(set) var decryptedMedia: [PairDecryptedMedia] = []
    private(set) var account: PairDevelopmentAccount?
    private(set) var invitationToken: String?
    private(set) var isWorking = false
    private(set) var isImporting = false
    private(set) var deletingMediaIDs: Set<String> = []
    var errorMessage: String?

    var canRevokePartner: Bool {
        guard let session,
              let vault = currentVault,
              vault.status == "active",
              vault.members.contains(where: {
                  $0.userID == session.userID && $0.role == "creator" && $0.status == "active"
              }) else { return false }
        return vault.members.contains { $0.userID != session.userID && $0.status == "active" }
    }

    @ObservationIgnored private let dependencies: PairVaultDependencies
    @ObservationIgnored private var session: PairSession?
    @ObservationIgnored private var device: PairDevice?
    @ObservationIgnored private var currentVault: PairVaultRecord?
    @ObservationIgnored private var vaultKey: Data?
    @ObservationIgnored private var requestEphemeralPrivateKey: Data?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var lockTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var securityGeneration = 0

    init(dependencies: PairVaultDependencies) {
        self.dependencies = dependencies
    }

    convenience init() {
        self.init(dependencies: .live())
    }

    #if DEBUG
    static func preview(phase: PairVaultScreenPhase) -> PairVaultStore {
        let store = PairVaultStore()
        store.phase = phase
        switch phase {
        case .waitingForPartner(let vault), .locked(let vault), .unlocked(let vault, _):
            store.currentVault = vault
        default:
            break
        }
        return store
    }
    #endif

    func signIn(as selectedAccount: PairDevelopmentAccount) async {
        guard !isWorking else { return }
        logout()
        isWorking = true
        phase = .loading
        account = selectedAccount
        defer { isWorking = false }

        do {
            let newSession = try await dependencies.api.developmentSession(selectedAccount)
            let privateKey = try dependencies.secrets.identityPrivateKey(
                accountID: newSession.userID,
                cryptography: dependencies.cryptography
            )
            let publicKey = try dependencies.cryptography.publicKey(for: privateKey)
            let deviceID = "ios-" + dependencies.cryptography.sha256Hex(publicKey.base64EncodedString()).prefix(32)
            let expectedDeviceID = String(deviceID)
            let registeredDevice = try await dependencies.api.registerDevice(
                session: newSession,
                deviceID: expectedDeviceID,
                publicKey: publicKey
            )
            guard registeredDevice.deviceID == expectedDeviceID,
                  registeredDevice.userID == newSession.userID,
                  registeredDevice.agreementPublicKey == publicKey.base64EncodedString() else {
                throw PairVaultError.contextMismatch
            }
            session = newSession
            device = registeredDevice
            try await refresh()
            startPolling()
        } catch {
            clearSession()
            account = selectedAccount
            phase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func createVault(named rawName: String) async {
        guard !isWorking,
              let account,
              let session,
              let device,
              case .ready = phase else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter a private name for the Pair vault."
            return
        }

        isWorking = true
        defer { isWorking = false }
        let vaultID = UUID().uuidString.lowercased()
        var shareWasSaved = false

        do {
            let partnerSession = try await dependencies.api.developmentSession(account.partner)
            let partnerDevice = try await dependencies.api.device(for: partnerSession.userID, session: session)
            guard partnerDevice.userID == partnerSession.userID,
                  let partnerPublicKey = Data(base64Encoded: partnerDevice.agreementPublicKey) else {
                throw PairVaultError.malformedData
            }

            let createdAtMS = Self.nowMS
            let expiresAtMS = createdAtMS + 24 * 60 * 60 * 1_000
            let invitationID = UUID().uuidString.lowercased()
            let token = try dependencies.cryptography.randomToken()
            let invitationContext = PairInvitationContext(
                protocolName: "woven-pair-v2",
                purpose: "invitation-share",
                vaultID: vaultID,
                invitationID: invitationID,
                membershipVersion: 1,
                creatorAccountID: session.userID,
                creatorDeviceID: device.deviceID,
                targetAccountID: partnerDevice.userID,
                targetDeviceID: partnerDevice.deviceID,
                createdAtMS: createdAtMS,
                expiresAtMS: expiresAtMS
            )

            let generatedVaultKey = try dependencies.cryptography.generateVaultKey()
            let shares = try dependencies.cryptography.split(generatedVaultKey)
            let creatorIdentity = try dependencies.secrets.identityPrivateKey(
                accountID: session.userID,
                cryptography: dependencies.cryptography
            )
            let envelope = try dependencies.cryptography.sealShare(
                shares.partner,
                recipientPublicKey: partnerPublicKey,
                context: invitationContext,
                senderPrivateKey: creatorIdentity
            )
            let privateMetadata = try JSONEncoder.pairCanonical.encode(PairVaultPrivateMetadata(name: name))
            let encryptedMetadata = try dependencies.cryptography.seal(
                privateMetadata,
                vaultKey: generatedVaultKey,
                authenticatedData: try dependencies.cryptography.vaultMetadataAAD(vaultID: vaultID, membershipVersion: 1)
            )

            try dependencies.secrets.saveShare(shares.local, vaultID: vaultID, accountID: session.userID)
            shareWasSaved = true
            try dependencies.secrets.saveInvitationToken(token, vaultID: vaultID, accountID: session.userID)
            let response = try await dependencies.api.createVault(
                session: session,
                vaultID: vaultID,
                creatorDeviceID: device.deviceID,
                encryptedMetadata: encryptedMetadata.base64EncodedString(),
                invitationID: invitationID,
                target: partnerDevice,
                tokenHash: dependencies.cryptography.sha256Hex(token),
                encryptedShareEnvelope: envelope,
                createdAtMS: createdAtMS,
                expiresAtMS: expiresAtMS
            )
            guard response.vault.vaultID == vaultID,
                  response.vault.encryptedMetadata == encryptedMetadata.base64EncodedString(),
                  response.vault.membershipVersion == 1,
                  response.vault.status == "pending",
                  response.vault.createdAtMS == createdAtMS,
                  response.vault.members.count == 1,
                  response.vault.members.first?.userID == session.userID,
                  response.vault.members.first?.deviceID == device.deviceID,
                  response.invitation.invitationID == invitationID,
                  response.invitation.vaultID == vaultID,
                  response.invitation.status == "pending",
                  response.invitation.context == invitationContext else {
                throw PairVaultError.contextMismatch
            }
            currentVault = response.vault
            invitationToken = token
            phase = .waitingForPartner(response.vault)
        } catch {
            if shareWasSaved {
                dependencies.secrets.deleteShare(vaultID: vaultID, accountID: session.userID)
                dependencies.secrets.deleteInvitationToken(vaultID: vaultID, accountID: session.userID)
            }
            errorMessage = error.localizedDescription
        }
    }

    func acceptInvitation(token rawToken: String) async {
        guard !isWorking,
              let session,
              let device,
              case .invitation(let invitation) = phase else { return }
        let token = rawToken.filter { !$0.isWhitespace }.lowercased()
        guard !token.isEmpty else {
            errorMessage = "Enter the invitation code from your partner."
            return
        }
        isWorking = true
        defer { isWorking = false }
        var savedShare = false

        do {
            guard invitation.context.protocolName == "woven-pair-v2",
                  invitation.context.purpose == "invitation-share",
                  invitation.context.targetAccountID == session.userID,
                  invitation.context.targetDeviceID == device.deviceID,
                  invitation.context.expiresAtMS > Self.nowMS,
                  let envelope = invitation.encryptedShareEnvelope else {
                throw PairVaultError.contextMismatch
            }
            let identity = try dependencies.secrets.identityPrivateKey(
                accountID: session.userID,
                cryptography: dependencies.cryptography
            )
            let creatorDevice = try await dependencies.api.device(
                for: invitation.context.creatorAccountID,
                session: session
            )
            guard creatorDevice.deviceID == invitation.context.creatorDeviceID,
                  creatorDevice.userID == invitation.context.creatorAccountID,
                  let creatorPublicKey = Data(base64Encoded: creatorDevice.agreementPublicKey) else {
                throw PairVaultError.contextMismatch
            }
            let partnerShare = try dependencies.cryptography.openShare(
                envelope,
                recipientPrivateKey: identity,
                context: invitation.context,
                expectedSenderPublicKey: creatorPublicKey
            )
            try dependencies.secrets.saveShare(
                partnerShare,
                vaultID: invitation.vaultID,
                accountID: session.userID
            )
            savedShare = true
            let response = try await dependencies.api.acceptInvitation(
                id: invitation.invitationID,
                token: token,
                session: session
            )
            guard response.vault.vaultID == invitation.vaultID,
                  response.vault.status == "active",
                  response.vault.membershipVersion == invitation.context.membershipVersion,
                  response.vault.createdAtMS == invitation.context.createdAtMS,
                  response.vault.members.count == 2,
                  response.vault.members.contains(where: {
                      $0.userID == session.userID
                          && $0.deviceID == device.deviceID
                          && $0.status == "active"
                  }),
                  response.vault.members.contains(where: {
                      $0.userID == invitation.context.creatorAccountID
                          && $0.deviceID == invitation.context.creatorDeviceID
                          && $0.status == "active"
                  }),
                  response.invitation.context == invitation.context,
                  response.invitation.status == "accepted" else {
                throw PairVaultError.contextMismatch
            }
            currentVault = response.vault
            phase = .locked(response.vault)
            invitationToken = nil
        } catch {
            if savedShare {
                dependencies.secrets.deleteShare(vaultID: invitation.vaultID, accountID: session.userID)
            }
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async throws {
        guard let session else { return }
        let invitations = try await dependencies.api.invitations(session: session)
        let vaults = try await dependencies.api.vaults(session: session)
        incomingRequests = try await dependencies.api.incomingAccessRequests(session: session)

        if let active = vaults.first(where: { $0.status == "active" }) {
            if currentVault?.membershipVersion != active.membershipVersion { lock() }
            currentVault = active
            if vaultKey == nil { phase = .locked(active) }
        } else if let invitation = invitations.first {
            currentVault = nil
            invitationToken = nil
            phase = .invitation(invitation)
        } else if let pending = vaults.first(where: { $0.status == "pending" }) {
            currentVault = pending
            invitationToken = try dependencies.secrets.invitationToken(
                vaultID: pending.vaultID,
                accountID: session.userID
            )
            phase = .waitingForPartner(pending)
        } else {
            if let previousVault = currentVault {
                lock()
                dependencies.secrets.deleteShare(
                    vaultID: previousVault.vaultID,
                    accountID: session.userID
                )
                dependencies.secrets.deleteInvitationToken(
                    vaultID: previousVault.vaultID,
                    accountID: session.userID
                )
            }
            currentVault = nil
            invitationToken = nil
            accessPhase = .none
            phase = .ready
        }
    }

    func requestAccess() async {
        guard !isWorking,
              let session,
              let device,
              let vault = currentVault,
              case .locked = phase else { return }
        isWorking = true
        accessPhase = .creatingRequest
        defer { isWorking = false }

        do {
            _ = try dependencies.secrets.share(vaultID: vault.vaultID, accountID: session.userID)
            guard let approver = vault.members.first(where: {
                $0.userID != session.userID && $0.status == "active"
            }) else {
                throw PairVaultError.contextMismatch
            }
            let ephemeralPrivate = dependencies.cryptography.generateIdentityPrivateKey()
            let ephemeralPublic = try dependencies.cryptography.publicKey(for: ephemeralPrivate)
            let createdAtMS = Self.nowMS
            let expiresAtMS = createdAtMS + 2 * 60 * 1_000
            let requestID = UUID().uuidString.lowercased()
            let record = try await dependencies.api.createAccessRequest(
                vaultID: vault.vaultID,
                requestID: requestID,
                requesterDeviceID: device.deviceID,
                ephemeralPublicKey: ephemeralPublic,
                createdAtMS: createdAtMS,
                expiresAtMS: expiresAtMS,
                session: session
            )
            let expectedContext = PairAccessContext(
                protocolName: "woven-pair-v2",
                purpose: "access-share",
                vaultID: vault.vaultID,
                requestID: requestID,
                membershipVersion: vault.membershipVersion,
                requesterAccountID: session.userID,
                requesterDeviceID: device.deviceID,
                requesterEphemeralPublicKey: ephemeralPublic.base64EncodedString(),
                approverAccountID: approver.userID,
                approverDeviceID: approver.deviceID,
                createdAtMS: createdAtMS,
                expiresAtMS: expiresAtMS
            )
            guard record.requestID == requestID,
                  record.vaultID == vault.vaultID,
                  record.status == .pending,
                  record.context == expectedContext else {
                throw PairVaultError.contextMismatch
            }
            requestEphemeralPrivateKey = ephemeralPrivate
            accessPhase = .awaitingApproval(record)
        } catch {
            requestEphemeralPrivateKey = nil
            accessPhase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func approve(_ request: PairAccessRecord) async {
        guard !isWorking,
              let session,
              let device,
              let vault = currentVault else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            guard request.status == .pending,
                  request.context.protocolName == "woven-pair-v2",
                  request.context.purpose == "access-share",
                  request.context.vaultID == vault.vaultID,
                  request.context.membershipVersion == vault.membershipVersion,
                  request.context.approverAccountID == session.userID,
                  request.context.approverDeviceID == device.deviceID,
                  request.context.expiresAtMS > Self.nowMS,
                  let requester = vault.members.first(where: {
                      $0.userID == request.context.requesterAccountID && $0.status == "active"
                  }),
                  requester.userID != session.userID,
                  requester.deviceID == request.context.requesterDeviceID,
                  let requesterPublic = Data(base64Encoded: request.context.requesterEphemeralPublicKey) else {
                throw PairVaultError.contextMismatch
            }
            try await dependencies.authenticate("Approve one-time access to this Pair vault")
            let share = try dependencies.secrets.share(vaultID: vault.vaultID, accountID: session.userID)
            let identity = try dependencies.secrets.identityPrivateKey(
                accountID: session.userID,
                cryptography: dependencies.cryptography
            )
            let envelope = try dependencies.cryptography.sealShare(
                share,
                recipientPublicKey: requesterPublic,
                context: request.context,
                senderPrivateKey: identity
            )
            let approved = try await dependencies.api.approveAccessRequest(
                id: request.requestID,
                envelope: envelope,
                session: session
            )
            guard approved.requestID == request.requestID,
                  approved.status == .approved,
                  approved.context == request.context else {
                throw PairVaultError.contextMismatch
            }
            incomingRequests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deny(_ request: PairAccessRecord) async {
        guard let session else { return }
        do {
            try await dependencies.api.denyAccessRequest(id: request.requestID, session: session)
            incomingRequests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelAccessRequest() async {
        guard let session,
              case .awaitingApproval(let request) = accessPhase else { return }
        do {
            try await dependencies.api.cancelAccessRequest(id: request.requestID, session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
        requestEphemeralPrivateKey = nil
        accessPhase = .cancelled
    }

    func importPhoto(_ plaintext: Data) async {
        guard !plaintext.isEmpty,
              !isImporting,
              let session,
              let vault = currentVault,
              let vaultKey,
              case .unlocked = phase else { return }
        isImporting = true
        defer { isImporting = false }
        let generation = securityGeneration

        do {
            let mediaID = UUID().uuidString.lowercased()
            let createdAtMS = Self.nowMS
            let metadata = PairMediaPrivateMetadata(
                mediaID: mediaID,
                createdAtMS: createdAtMS,
                mediaType: "image"
            )
            let encryptedMetadata = try dependencies.cryptography.seal(
                JSONEncoder.pairCanonical.encode(metadata),
                vaultKey: vaultKey,
                authenticatedData: try dependencies.cryptography.mediaAAD(
                    vaultID: vault.vaultID,
                    mediaID: mediaID,
                    membershipVersion: vault.membershipVersion,
                    purpose: "media-metadata"
                )
            )
            let encryptedPhoto = try dependencies.cryptography.seal(
                plaintext,
                vaultKey: vaultKey,
                authenticatedData: try dependencies.cryptography.mediaAAD(
                    vaultID: vault.vaultID,
                    mediaID: mediaID,
                    membershipVersion: vault.membershipVersion,
                    purpose: "media-blob"
                )
            )
            let uploaded = try await dependencies.api.uploadMedia(
                vaultID: vault.vaultID,
                mediaID: mediaID,
                encryptedBlob: encryptedPhoto,
                encryptedMetadata: encryptedMetadata,
                createdAtMS: createdAtMS,
                session: session
            )
            guard uploaded.mediaID == mediaID,
                  uploaded.vaultID == vault.vaultID,
                  uploaded.encryptedMetadata == encryptedMetadata.base64EncodedString(),
                  uploaded.createdAtMS == createdAtMS else {
                throw PairVaultError.contextMismatch
            }
            if generation == securityGeneration, self.vaultKey != nil {
                decryptedMedia.append(PairDecryptedMedia(id: mediaID, createdAtMS: createdAtMS, imageData: plaintext))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMedia(id: String) async {
        guard !deletingMediaIDs.contains(id),
              let session,
              let vault = currentVault,
              case .unlocked = phase else { return }
        deletingMediaIDs.insert(id)
        defer { deletingMediaIDs.remove(id) }
        do {
            try await dependencies.api.deleteMedia(vaultID: vault.vaultID, mediaID: id, session: session)
            decryptedMedia.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revokePartner() async {
        guard canRevokePartner,
              let session,
              let vault = currentVault,
              let partner = vault.members.first(where: { $0.userID != session.userID }) else { return }
        do {
            try await dependencies.api.revokeMember(vaultID: vault.vaultID, userID: partner.userID, session: session)
            lock()
            dependencies.secrets.deleteShare(vaultID: vault.vaultID, accountID: session.userID)
            currentVault = nil
            phase = .ready
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pollOnce() async {
        guard let session else { return }
        do {
            try await refresh()
            guard case .awaitingApproval(let original) = accessPhase else { return }
            let updated = try await dependencies.api.accessRequest(id: original.requestID, session: session)
            switch updated.status {
            case .pending:
                accessPhase = .awaitingApproval(updated)
            case .approved:
                accessPhase = .approved
                try await consumeApprovedRequest(original: original)
            case .denied:
                requestEphemeralPrivateKey = nil
                accessPhase = .denied
            case .expired:
                requestEphemeralPrivateKey = nil
                accessPhase = .expired
            case .cancelled:
                requestEphemeralPrivateKey = nil
                accessPhase = .cancelled
            case .consumed:
                requestEphemeralPrivateKey = nil
                accessPhase = .failed("This approval was already consumed.")
            }
        } catch {
            if case .awaitingApproval = accessPhase {
                requestEphemeralPrivateKey = nil
                accessPhase = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
            } else if accessPhase == .approved {
                requestEphemeralPrivateKey = nil
                accessPhase = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }

    func lock() {
        securityGeneration += 1
        lockTimeoutTask?.cancel()
        lockTimeoutTask = nil
        vaultKey = nil
        decryptedMedia.removeAll(keepingCapacity: false)
        requestEphemeralPrivateKey = nil
        if case .unlocked(let vault, _) = phase { phase = .locked(vault) }
        if case .awaitingApproval = accessPhase { accessPhase = .cancelled }
        else if accessPhase == .consumed { accessPhase = .none }
    }

    func logout() {
        lock()
        pollingTask?.cancel()
        pollingTask = nil
        clearSession()
        account = nil
        phase = .signedOut
        accessPhase = .none
        errorMessage = nil
    }

    func dismissError() {
        errorMessage = nil
        if case .failed = phase, session == nil { phase = .signedOut }
    }

    private func consumeApprovedRequest(original: PairAccessRecord) async throws {
        guard let session,
              let vault = currentVault,
              let ephemeralPrivate = requestEphemeralPrivateKey else {
            throw PairVaultError.contextMismatch
        }
        let response = try await dependencies.api.consumeAccessRequest(id: original.requestID, session: session)
        guard response.status == "consumed",
              response.context == original.context else {
            throw PairVaultError.contextMismatch
        }
        let approverDevice = try await dependencies.api.device(
            for: response.context.approverAccountID,
            session: session
        )
        guard approverDevice.deviceID == response.context.approverDeviceID,
              approverDevice.userID == response.context.approverAccountID,
              let approverPublic = Data(base64Encoded: approverDevice.agreementPublicKey) else {
            throw PairVaultError.contextMismatch
        }
        let remoteShare = try dependencies.cryptography.openShare(
            response.encryptedShareEnvelope,
            recipientPrivateKey: ephemeralPrivate,
            context: response.context,
            expectedSenderPublicKey: approverPublic
        )
        let localShare = try dependencies.secrets.share(vaultID: vault.vaultID, accountID: session.userID)
        let reconstructedKey = try dependencies.cryptography.combine(localShare, remoteShare)
        let unlocked = try await decryptVault(vault, key: reconstructedKey, session: session)

        requestEphemeralPrivateKey = nil
        vaultKey = reconstructedKey
        decryptedMedia = unlocked.media
        phase = .unlocked(vault, name: unlocked.name)
        accessPhase = .consumed
        startLockTimeout()
    }

    private func decryptVault(
        _ vault: PairVaultRecord,
        key: Data,
        session: PairSession
    ) async throws -> (name: String, media: [PairDecryptedMedia]) {
        guard let encryptedMetadata = Data(base64Encoded: vault.encryptedMetadata) else {
            throw PairVaultError.malformedData
        }
        let metadataData = try dependencies.cryptography.open(
            encryptedMetadata,
            vaultKey: key,
            authenticatedData: try dependencies.cryptography.vaultMetadataAAD(
                vaultID: vault.vaultID,
                membershipVersion: vault.membershipVersion
            )
        )
        let metadata = try JSONDecoder().decode(PairVaultPrivateMetadata.self, from: metadataData)
        let summaries = try await dependencies.api.listMedia(vaultID: vault.vaultID, session: session)
        var media: [PairDecryptedMedia] = []
        for summary in summaries {
            let record = try await dependencies.api.downloadMedia(
                vaultID: vault.vaultID,
                mediaID: summary.mediaID,
                session: session
            )
            guard let encryptedBlobString = record.encryptedBlob,
                  let encryptedBlob = Data(base64Encoded: encryptedBlobString),
                  let encryptedMediaMetadata = Data(base64Encoded: record.encryptedMetadata) else {
                throw PairVaultError.malformedData
            }
            let mediaMetadataData = try dependencies.cryptography.open(
                encryptedMediaMetadata,
                vaultKey: key,
                authenticatedData: try dependencies.cryptography.mediaAAD(
                    vaultID: vault.vaultID,
                    mediaID: record.mediaID,
                    membershipVersion: vault.membershipVersion,
                    purpose: "media-metadata"
                )
            )
            let privateMetadata = try JSONDecoder().decode(PairMediaPrivateMetadata.self, from: mediaMetadataData)
            guard privateMetadata.mediaID == record.mediaID,
                  privateMetadata.createdAtMS == record.createdAtMS,
                  privateMetadata.mediaType == "image" else {
                throw PairVaultError.contextMismatch
            }
            let plaintext = try dependencies.cryptography.open(
                encryptedBlob,
                vaultKey: key,
                authenticatedData: try dependencies.cryptography.mediaAAD(
                    vaultID: vault.vaultID,
                    mediaID: record.mediaID,
                    membershipVersion: vault.membershipVersion,
                    purpose: "media-blob"
                )
            )
            media.append(PairDecryptedMedia(id: record.mediaID, createdAtMS: record.createdAtMS, imageData: plaintext))
        }
        return (metadata.name, media.sorted { $0.createdAtMS > $1.createdAtMS })
    }

    private func startPolling() {
        pollingTask?.cancel()
        let events = dependencies.updates.events()
        pollingTask = Task { [weak self] in
            for await _ in events {
                guard !Task.isCancelled else { return }
                await self?.pollOnce()
            }
        }
    }

    private func startLockTimeout() {
        lockTimeoutTask?.cancel()
        let timeout = dependencies.lockTimeout
        lockTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.lock()
        }
    }

    private func clearSession() {
        session = nil
        device = nil
        currentVault = nil
        vaultKey = nil
        requestEphemeralPrivateKey = nil
        decryptedMedia = []
        incomingRequests = []
        invitationToken = nil
    }

    nonisolated private static var nowMS: Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}
