import Foundation
import Observation

struct SoloVaultDependencies {
    let repository: SoloVaultRepository
    let cryptography: SoloVaultCryptography
    let saveKey: (Data, UUID) async throws -> Void
    let loadKey: (UUID) async throws -> Data
    let deleteKey: (UUID) async throws -> Void
    let authenticate: (String) async throws -> Void

    @MainActor
    static func live() -> Self {
        let keyStore = KeychainSoloVaultKeyStore()
        let authenticator = SoloVaultDeviceAuthenticator()

        return SoloVaultDependencies(
            repository: SoloVaultRepository(),
            cryptography: SoloVaultCryptography(),
            saveKey: { keyMaterial, vaultID in
                try await keyStore.save(keyMaterial, for: vaultID)
            },
            loadKey: { vaultID in
                try await keyStore.load(for: vaultID)
            },
            deleteKey: { vaultID in
                try await keyStore.delete(for: vaultID)
            },
            authenticate: { reason in
                try await authenticator.authenticate(reason: reason)
            }
        )
    }
}

@MainActor
@Observable
final class SoloVaultStore {
    private(set) var phase: SoloVaultPhase = .loading
    private(set) var decryptedPhotos: [UUID: Data] = [:]
    private(set) var isCreating = false
    private(set) var isImporting = false
    private(set) var isUnlocking = false
    private(set) var deletingPhotoIDs: Set<UUID> = []
    var errorMessage: String?

    private let dependencies: SoloVaultDependencies
    private var keyMaterial: Data?
    private var hasBootstrapped = false
    private var securityGeneration = 0

    init(dependencies: SoloVaultDependencies) {
        self.dependencies = dependencies
    }

    convenience init() {
        self.init(dependencies: .live())
    }

    func bootstrap(force: Bool = false) async {
        guard force || !hasBootstrapped else { return }
        hasBootstrapped = true
        clearSensitiveData()
        phase = .loading

        do {
            if let manifest = try await dependencies.repository.loadVault() {
                phase = .locked(manifest.summary)
            } else {
                phase = .noVault
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func createVault(named rawName: String) async -> Bool {
        guard case .noVault = phase, !isCreating else { return false }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter a name for your Solo vault."
            return false
        }

        isCreating = true
        defer { isCreating = false }

        let generation = securityGeneration
        let vaultID = UUID()
        var keyWasSaved = false

        do {
            let newKey = await dependencies.cryptography.generateKeyMaterial()
            try await dependencies.saveKey(newKey, vaultID)
            keyWasSaved = true

            let manifest = try await dependencies.repository.createVault(
                id: vaultID,
                name: name,
                createdAt: Date()
            )

            if generation == securityGeneration {
                keyMaterial = newKey
                decryptedPhotos = [:]
                phase = .unlocked(manifest)
            } else {
                phase = .locked(manifest.summary)
            }
            return true
        } catch {
            if keyWasSaved {
                try? await dependencies.deleteKey(vaultID)
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func importPhoto(_ plaintext: Data) async {
        guard !plaintext.isEmpty,
              !isImporting,
              let keyMaterial,
              case .unlocked(let manifest) = phase else {
            if plaintext.isEmpty {
                errorMessage = "The selected photo did not contain readable data."
            }
            return
        }

        isImporting = true
        defer { isImporting = false }

        let generation = securityGeneration
        let mediaID = UUID()
        let createdAt = Date()
        let authenticatedData = Self.authenticatedData(
            vaultID: manifest.id,
            mediaID: mediaID
        )

        do {
            let sealedData = try await dependencies.cryptography.seal(
                plaintext,
                keyMaterial: keyMaterial,
                authenticatedData: authenticatedData
            )
            let result = try await dependencies.repository.addEncryptedPhoto(
                id: mediaID,
                createdAt: createdAt,
                encryptedData: sealedData
            )

            if generation == securityGeneration,
               case .unlocked(let currentManifest) = phase,
               currentManifest.id == manifest.id {
                decryptedPhotos[mediaID] = plaintext
                phase = .unlocked(result.manifest)
            } else if case .locked(let summary) = phase, summary.id == manifest.id {
                phase = .locked(result.manifest.summary)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unlock() async {
        guard !isUnlocking, case .locked(let summary) = phase else { return }

        isUnlocking = true
        defer { isUnlocking = false }
        let generation = securityGeneration

        do {
            try await dependencies.authenticate("Unlock your Woven Solo vault")
            guard generation == securityGeneration else { return }

            let loadedKey = try await dependencies.loadKey(summary.id)
            guard generation == securityGeneration else { return }

            guard let manifest = try await dependencies.repository.loadVault(),
                  manifest.id == summary.id else {
                throw SoloVaultError.corruptStorage
            }

            var plaintextByID: [UUID: Data] = [:]
            for record in manifest.media {
                let sealedData = try await dependencies.repository.encryptedPhoto(for: record)
                let plaintext = try await dependencies.cryptography.open(
                    sealedData,
                    keyMaterial: loadedKey,
                    authenticatedData: Self.authenticatedData(
                        vaultID: manifest.id,
                        mediaID: record.id
                    )
                )
                guard generation == securityGeneration else { return }
                plaintextByID[record.id] = plaintext
            }

            keyMaterial = loadedKey
            decryptedPhotos = plaintextByID
            phase = .unlocked(manifest)
        } catch is CancellationError {
            clearSensitiveData()
            phase = .locked(summary)
        } catch {
            clearSensitiveData()
            phase = .locked(summary)
            errorMessage = error.localizedDescription
        }
    }

    func lock() {
        securityGeneration += 1

        if case .unlocked(let manifest) = phase {
            phase = .locked(manifest.summary)
        }

        clearSensitiveData()
    }

    func deletePhoto(id: UUID) async {
        guard !deletingPhotoIDs.contains(id),
              case .unlocked(let manifest) = phase else { return }

        deletingPhotoIDs.insert(id)
        defer { deletingPhotoIDs.remove(id) }
        let generation = securityGeneration

        do {
            let updatedManifest = try await dependencies.repository.deletePhoto(id: id)

            if generation == securityGeneration,
               case .unlocked(let currentManifest) = phase,
               currentManifest.id == manifest.id {
                decryptedPhotos[id] = nil
                phase = .unlocked(updatedManifest)
            } else if case .locked(let summary) = phase, summary.id == manifest.id {
                phase = .locked(updatedManifest.summary)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retryLoading() async {
        await bootstrap(force: true)
    }

    func presentError(_ message: String) {
        errorMessage = message
    }

    func dismissError() {
        errorMessage = nil
    }

    private func clearSensitiveData() {
        keyMaterial = nil
        decryptedPhotos.removeAll(keepingCapacity: false)
    }

    nonisolated static func authenticatedData(vaultID: UUID, mediaID: UUID) -> Data {
        Data(
            "woven.solo.v1|\(vaultID.uuidString.lowercased())|\(mediaID.uuidString.lowercased())"
                .utf8
        )
    }
}
