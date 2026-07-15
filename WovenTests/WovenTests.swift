import Foundation
import Testing
@testable import Woven

struct SoloVaultCryptographyTests {
    @Test
    func aesGCMRoundTripAndTamperDetection() async throws {
        let cryptography = SoloVaultCryptography()
        let key = await cryptography.generateKeyMaterial()
        let plaintext = Data("private-photo-bytes".utf8)
        let authenticatedData = Data("vault-and-media-identity".utf8)

        let sealed = try await cryptography.seal(
            plaintext,
            keyMaterial: key,
            authenticatedData: authenticatedData
        )
        let opened = try await cryptography.open(
            sealed,
            keyMaterial: key,
            authenticatedData: authenticatedData
        )

        #expect(sealed != plaintext)
        #expect(opened == plaintext)

        var tampered = sealed
        tampered[tampered.startIndex] = tampered[tampered.startIndex] ^ 0x01

        do {
            _ = try await cryptography.open(
                tampered,
                keyMaterial: key,
                authenticatedData: authenticatedData
            )
            Issue.record("Tampered AES-GCM data unexpectedly decrypted")
        } catch {
            #expect(error as? SoloVaultError == .authenticationTagMismatch)
        }

        do {
            _ = try await cryptography.open(
                sealed,
                keyMaterial: key,
                authenticatedData: Data("different-identity".utf8)
            )
            Issue.record("AES-GCM data unexpectedly decrypted with different authenticated data")
        } catch {
            #expect(error as? SoloVaultError == .authenticationTagMismatch)
        }
    }
}

struct SoloVaultRepositoryTests {
    @Test
    func encryptedMediaPersistsAndDeletesWithoutPlaintextFiles() async throws {
        let rootURL = makeTemporaryVaultURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let repository = SoloVaultRepository(rootURL: rootURL)
        let cryptography = SoloVaultCryptography()
        let vaultID = UUID()
        let mediaID = UUID()
        let plaintext = Data("recognizable-plaintext-photo-payload".utf8)
        let key = await cryptography.generateKeyMaterial()
        let authenticatedData = SoloVaultStore.authenticatedData(
            vaultID: vaultID,
            mediaID: mediaID
        )

        _ = try await repository.createVault(
            id: vaultID,
            name: "Test Vault",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let sealed = try await cryptography.seal(
            plaintext,
            keyMaterial: key,
            authenticatedData: authenticatedData
        )
        let persisted = try await repository.addEncryptedPhoto(
            id: mediaID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            encryptedData: sealed
        )

        let encryptedFileURL = rootURL
            .appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent(persisted.record.encryptedFileName)
        let bytesOnDisk = try Data(contentsOf: encryptedFileURL)

        #expect(bytesOnDisk == sealed)
        #expect(bytesOnDisk != plaintext)
        #expect(bytesOnDisk.range(of: plaintext) == nil)

        let relaunchedRepository = SoloVaultRepository(rootURL: rootURL)
        let relaunchedManifest = try #require(await relaunchedRepository.loadVault())
        #expect(relaunchedManifest.media == [persisted.record])

        let reopenedSealedData = try await relaunchedRepository.encryptedPhoto(
            for: persisted.record
        )
        let reopenedPlaintext = try await cryptography.open(
            reopenedSealedData,
            keyMaterial: key,
            authenticatedData: authenticatedData
        )
        #expect(reopenedPlaintext == plaintext)

        let afterDeletion = try await relaunchedRepository.deletePhoto(id: mediaID)
        #expect(afterDeletion.media.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: encryptedFileURL.path))
    }
}

@MainActor
struct SoloVaultStateTests {
    @Test
    func createImportLockRelaunchUnlockAndDeleteFlow() async throws {
        let rootURL = makeTemporaryVaultURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let repository = SoloVaultRepository(rootURL: rootURL)
        let cryptography = SoloVaultCryptography()
        let keyStore = TestSoloVaultKeyStore()
        let dependencies = makeDependencies(
            repository: repository,
            cryptography: cryptography,
            keyStore: keyStore
        )
        let photoData = Data("in-memory-photo-payload-that-must-be-cleared-on-lock".utf8)

        let firstLaunchStore = SoloVaultStore(dependencies: dependencies)
        await firstLaunchStore.bootstrap()
        #expect(firstLaunchStore.phase == .noVault)

        #expect(await firstLaunchStore.createVault(named: "My Solo Vault"))
        guard case .unlocked = firstLaunchStore.phase else {
            Issue.record("Vault was not unlocked after creation")
            return
        }

        await firstLaunchStore.importPhoto(photoData)
        guard case .unlocked(let importedManifest) = firstLaunchStore.phase,
              let record = importedManifest.media.first else {
            Issue.record("Photo import did not update the unlocked manifest")
            return
        }
        #expect(firstLaunchStore.decryptedPhotos[record.id] == photoData)

        firstLaunchStore.lock()
        #expect(firstLaunchStore.decryptedPhotos.isEmpty)
        guard case .locked(let lockedSummary) = firstLaunchStore.phase else {
            Issue.record("Vault did not enter the locked state")
            return
        }
        #expect(lockedSummary.photoCount == 1)

        let relaunchedStore = SoloVaultStore(dependencies: dependencies)
        await relaunchedStore.bootstrap()
        #expect(relaunchedStore.decryptedPhotos.isEmpty)
        guard case .locked(let relaunchedSummary) = relaunchedStore.phase else {
            Issue.record("Persisted vault was not locked on relaunch")
            return
        }
        #expect(relaunchedSummary.photoCount == 1)

        await relaunchedStore.unlock()
        guard case .unlocked(let reopenedManifest) = relaunchedStore.phase else {
            Issue.record("Vault did not unlock after successful device authentication")
            return
        }
        #expect(relaunchedStore.decryptedPhotos[record.id] == photoData)

        await relaunchedStore.deletePhoto(id: record.id)
        guard case .unlocked(let emptyManifest) = relaunchedStore.phase else {
            Issue.record("Vault left the unlocked state after deletion")
            return
        }
        #expect(emptyManifest.media.isEmpty)
        #expect(relaunchedStore.decryptedPhotos.isEmpty)

        let persistedManifest = try #require(await repository.loadVault())
        #expect(persistedManifest.media.isEmpty)
        #expect(reopenedManifest.id == persistedManifest.id)
    }
}

private actor TestSoloVaultKeyStore {
    private var keys: [UUID: Data] = [:]

    func save(_ data: Data, for vaultID: UUID) {
        keys[vaultID] = data
    }

    func load(for vaultID: UUID) throws -> Data {
        guard let data = keys[vaultID] else {
            throw SoloVaultError.invalidKey
        }
        return data
    }

    func delete(for vaultID: UUID) {
        keys[vaultID] = nil
    }
}

@MainActor
private func makeDependencies(
    repository: SoloVaultRepository,
    cryptography: SoloVaultCryptography,
    keyStore: TestSoloVaultKeyStore
) -> SoloVaultDependencies {
    SoloVaultDependencies(
        repository: repository,
        cryptography: cryptography,
        saveKey: { data, vaultID in
            await keyStore.save(data, for: vaultID)
        },
        loadKey: { vaultID in
            try await keyStore.load(for: vaultID)
        },
        deleteKey: { vaultID in
            await keyStore.delete(for: vaultID)
        },
        authenticate: { _ in }
    )
}

private func makeTemporaryVaultURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WovenTests-\(UUID().uuidString)", isDirectory: true)
}
