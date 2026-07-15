import CryptoKit
import Foundation

actor SoloVaultCryptography {
    func generateKeyMaterial() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    func seal(_ plaintext: Data, keyMaterial: Data, authenticatedData: Data) throws -> Data {
        let key = try symmetricKey(from: keyMaterial)
        let sealedBox = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: authenticatedData
        )

        guard let combined = sealedBox.combined else {
            throw SoloVaultError.encryptionFailed
        }

        return combined
    }

    func open(_ sealedData: Data, keyMaterial: Data, authenticatedData: Data) throws -> Data {
        let key = try symmetricKey(from: keyMaterial)

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
            return try AES.GCM.open(
                sealedBox,
                using: key,
                authenticating: authenticatedData
            )
        } catch {
            throw SoloVaultError.authenticationTagMismatch
        }
    }

    private func symmetricKey(from keyMaterial: Data) throws -> SymmetricKey {
        guard keyMaterial.count == 32 else {
            throw SoloVaultError.invalidKey
        }
        return SymmetricKey(data: keyMaterial)
    }
}

