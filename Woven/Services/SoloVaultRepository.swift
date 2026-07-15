import Foundation

actor SoloVaultRepository {
    let rootURL: URL

    private let fileManager: FileManager
    private let manifestFileName = "manifest.json"
    private let mediaDirectoryName = "media"

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.rootURL = applicationSupport
                .appendingPathComponent("Woven", isDirectory: true)
                .appendingPathComponent("SoloVault", isDirectory: true)
        }
    }

    func loadVault() throws -> SoloVaultManifest? {
        try ensureStorageExists()

        let url = manifestURL
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let manifest: SoloVaultManifest
        do {
            manifest = try decoder.decode(
                SoloVaultManifest.self,
                from: Data(contentsOf: url, options: .mappedIfSafe)
            )
        } catch {
            throw SoloVaultError.corruptStorage
        }

        guard manifest.schemaVersion == SoloVaultManifest.currentSchemaVersion else {
            throw SoloVaultError.unsupportedSchema
        }

        return manifest
    }

    func createVault(id: UUID, name: String, createdAt: Date) throws -> SoloVaultManifest {
        try ensureStorageExists()
        guard !fileManager.fileExists(atPath: manifestURL.path) else {
            throw SoloVaultError.vaultAlreadyExists
        }

        let manifest = SoloVaultManifest(id: id, name: name, createdAt: createdAt)
        try save(manifest)
        return manifest
    }

    func addEncryptedPhoto(
        id: UUID,
        createdAt: Date,
        encryptedData: Data
    ) throws -> (manifest: SoloVaultManifest, record: SoloVaultMediaRecord) {
        guard var manifest = try loadVault() else {
            throw SoloVaultError.vaultNotFound
        }

        let fileName = "\(id.uuidString.lowercased()).woven"
        let record = SoloVaultMediaRecord(
            id: id,
            createdAt: createdAt,
            encryptedFileName: fileName,
            encryptedByteCount: encryptedData.count
        )
        let destination = mediaDirectoryURL.appendingPathComponent(fileName, isDirectory: false)

        do {
            try encryptedData.write(
                to: destination,
                options: [.atomic, .completeFileProtection]
            )
            manifest.media.append(record)
            try save(manifest)
            return (manifest, record)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func encryptedPhoto(for record: SoloVaultMediaRecord) throws -> Data {
        let url = mediaDirectoryURL.appendingPathComponent(
            record.encryptedFileName,
            isDirectory: false
        )
        guard fileManager.fileExists(atPath: url.path) else {
            throw SoloVaultError.mediaNotFound
        }

        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw SoloVaultError.corruptStorage
        }
    }

    func deletePhoto(id: UUID) throws -> SoloVaultManifest {
        guard var manifest = try loadVault() else {
            throw SoloVaultError.vaultNotFound
        }
        guard let record = manifest.media.first(where: { $0.id == id }) else {
            throw SoloVaultError.mediaNotFound
        }

        let fileURL = mediaDirectoryURL.appendingPathComponent(
            record.encryptedFileName,
            isDirectory: false
        )
        let stagedURL = fileURL.appendingPathExtension("deleting")

        if fileManager.fileExists(atPath: stagedURL.path) {
            try fileManager.removeItem(at: stagedURL)
        }
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.moveItem(at: fileURL, to: stagedURL)
        }

        manifest.media.removeAll { $0.id == id }

        do {
            try save(manifest)
            if fileManager.fileExists(atPath: stagedURL.path) {
                try fileManager.removeItem(at: stagedURL)
            }
            return manifest
        } catch {
            if fileManager.fileExists(atPath: stagedURL.path) {
                try? fileManager.moveItem(at: stagedURL, to: fileURL)
            }
            throw error
        }
    }

    private var manifestURL: URL {
        rootURL.appendingPathComponent(manifestFileName, isDirectory: false)
    }

    private var mediaDirectoryURL: URL {
        rootURL.appendingPathComponent(mediaDirectoryName, isDirectory: true)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func ensureStorageExists() throws {
        try fileManager.createDirectory(
            at: mediaDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        var protectedRoot = rootURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? protectedRoot.setResourceValues(values)
    }

    private func save(_ manifest: SoloVaultManifest) throws {
        do {
            let data = try encoder.encode(manifest)
            try data.write(
                to: manifestURL,
                options: [.atomic, .completeFileProtection]
            )
        } catch {
            throw SoloVaultError.corruptStorage
        }
    }
}

