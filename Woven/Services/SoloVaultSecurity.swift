import Foundation
import LocalAuthentication
import Security

actor KeychainSoloVaultKeyStore {
    private let service = "com.zavier.Woven.solo-vault"

    func save(_ keyMaterial: Data, for vaultID: UUID) throws {
        let account = accountName(for: vaultID)
        let deleteStatus = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainSoloVaultError.unexpectedStatus(deleteStatus)
        }

        var query = baseQuery(account: account)
        query[kSecValueData as String] = keyMaterial
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainSoloVaultError.unexpectedStatus(status)
        }
    }

    func load(for vaultID: UUID) throws -> Data {
        var query = baseQuery(account: accountName(for: vaultID))
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                throw SoloVaultError.invalidKey
            }
            throw KeychainSoloVaultError.unexpectedStatus(status)
        }
        guard data.count == 32 else {
            throw SoloVaultError.invalidKey
        }
        return data
    }

    func delete(for vaultID: UUID) throws {
        let status = SecItemDelete(
            baseQuery(account: accountName(for: vaultID)) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSoloVaultError.unexpectedStatus(status)
        }
    }

    private func accountName(for vaultID: UUID) -> String {
        "solo-vault-key-\(vaultID.uuidString.lowercased())"
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

@MainActor
final class SoloVaultDeviceAuthenticator {
    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"

        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            throw SoloVaultError.authenticationUnavailable
        }

        do {
            guard try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) else {
                throw SoloVaultError.authenticationFailed
            }
        } catch let error as LAError {
            if error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
                throw CancellationError()
            }
            throw SoloVaultError.authenticationFailed
        }
    }
}

enum KeychainSoloVaultError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "The vault key could not be stored securely (Keychain status \(status))."
        }
    }
}

