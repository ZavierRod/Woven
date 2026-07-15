import CryptoKit
import Foundation
import Security

struct PairSealedEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let senderPublicKey: String
    let sealedBox: String
}

private struct PairVaultMetadataContext: Codable, Sendable {
    let protocolName: String
    let purpose: String
    let vaultID: String
    let membershipVersion: Int

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case purpose
        case vaultID = "vault_id"
        case membershipVersion = "membership_version"
    }
}

private struct PairMediaContext: Codable, Sendable {
    let protocolName: String
    let purpose: String
    let vaultID: String
    let mediaID: String
    let membershipVersion: Int

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case purpose
        case vaultID = "vault_id"
        case mediaID = "media_id"
        case membershipVersion = "membership_version"
    }
}

struct PairVaultCryptography: Sendable {
    static let keyByteCount = 32

    func generateIdentityPrivateKey() -> Data {
        Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    }

    func publicKey(for privateKey: Data) throws -> Data {
        try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
            .publicKey.rawRepresentation
    }

    func generateVaultKey() throws -> Data {
        try randomData(count: Self.keyByteCount)
    }

    func split(_ vaultKey: Data) throws -> (local: Data, partner: Data) {
        guard vaultKey.count == Self.keyByteCount else { throw PairVaultError.invalidKeyLength }
        let local = try randomData(count: Self.keyByteCount)
        return (local, try xor(local, vaultKey))
    }

    func combine(_ firstShare: Data, _ secondShare: Data) throws -> Data {
        try xor(firstShare, secondShare)
    }

    func sealShare(
        _ share: Data,
        recipientPublicKey: Data,
        context: some Encodable,
        senderPrivateKey: Data? = nil
    ) throws -> String {
        guard share.count == Self.keyByteCount else { throw PairVaultError.invalidKeyLength }
        let sender: Curve25519.KeyAgreement.PrivateKey
        if let senderPrivateKey {
            sender = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: senderPrivateKey)
        } else {
            sender = Curve25519.KeyAgreement.PrivateKey()
        }
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKey)
        let contextData = try canonicalData(context)
        let key = try derivedKey(privateKey: sender, publicKey: recipient, context: contextData)
        let sealed = try AES.GCM.seal(share, using: key, authenticating: contextData)
        guard let combined = sealed.combined else { throw PairVaultError.malformedData }
        let envelope = PairSealedEnvelope(
            version: 2,
            senderPublicKey: sender.publicKey.rawRepresentation.base64EncodedString(),
            sealedBox: combined.base64EncodedString()
        )
        return try JSONEncoder.pairCanonical.encode(envelope).base64EncodedString()
    }

    func openShare(
        _ encodedEnvelope: String,
        recipientPrivateKey: Data,
        context: some Encodable,
        expectedSenderPublicKey: Data? = nil
    ) throws -> Data {
        guard let envelopeData = Data(base64Encoded: encodedEnvelope),
              let envelope = try? JSONDecoder().decode(PairSealedEnvelope.self, from: envelopeData),
              envelope.version == 2,
              let senderData = Data(base64Encoded: envelope.senderPublicKey),
              let sealedData = Data(base64Encoded: envelope.sealedBox) else {
            throw PairVaultError.malformedData
        }
        if let expectedSenderPublicKey,
           !senderData.elementsEqual(expectedSenderPublicKey) {
            throw PairVaultError.contextMismatch
        }
        let recipient = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: recipientPrivateKey)
        let sender = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderData)
        let contextData = try canonicalData(context)
        let key = try derivedKey(privateKey: recipient, publicKey: sender, context: contextData)
        let sealed = try AES.GCM.SealedBox(combined: sealedData)
        let share = try AES.GCM.open(sealed, using: key, authenticating: contextData)
        guard share.count == Self.keyByteCount else { throw PairVaultError.invalidKeyLength }
        return share
    }

    func seal(_ plaintext: Data, vaultKey: Data, authenticatedData: Data) throws -> Data {
        guard vaultKey.count == Self.keyByteCount else { throw PairVaultError.invalidKeyLength }
        let box = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: vaultKey),
            authenticating: authenticatedData
        )
        guard let combined = box.combined else { throw PairVaultError.malformedData }
        return combined
    }

    func open(_ ciphertext: Data, vaultKey: Data, authenticatedData: Data) throws -> Data {
        guard vaultKey.count == Self.keyByteCount else { throw PairVaultError.invalidKeyLength }
        return try AES.GCM.open(
            AES.GCM.SealedBox(combined: ciphertext),
            using: SymmetricKey(data: vaultKey),
            authenticating: authenticatedData
        )
    }

    func canonicalData(_ value: some Encodable) throws -> Data {
        try JSONEncoder.pairCanonical.encode(value)
    }

    func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func randomToken() throws -> String {
        try randomData(count: 32).map { String(format: "%02x", $0) }.joined()
    }

    func vaultMetadataAAD(vaultID: String, membershipVersion: Int) throws -> Data {
        try canonicalData(
            PairVaultMetadataContext(
                protocolName: "woven-pair-v2",
                purpose: "vault-metadata",
                vaultID: vaultID,
                membershipVersion: membershipVersion
            )
        )
    }

    func mediaAAD(vaultID: String, mediaID: String, membershipVersion: Int, purpose: String) throws -> Data {
        try canonicalData(
            PairMediaContext(
                protocolName: "woven-pair-v2",
                purpose: purpose,
                vaultID: vaultID,
                mediaID: mediaID,
                membershipVersion: membershipVersion
            )
        )
    }

    private func derivedKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        publicKey: Curve25519.KeyAgreement.PublicKey,
        context: Data
    ) throws -> SymmetricKey {
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("woven-pair-v2-hkdf-salt".utf8),
            sharedInfo: context,
            outputByteCount: Self.keyByteCount
        )
    }

    private func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw PairVaultError.malformedData }
        return data
    }

    private func xor(_ left: Data, _ right: Data) throws -> Data {
        guard left.count == Self.keyByteCount, right.count == Self.keyByteCount else {
            throw PairVaultError.invalidKeyLength
        }
        return Data(zip(left, right).map { $0.0 ^ $0.1 })
    }
}

extension JSONEncoder {
    static var pairCanonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
