import CommonCrypto
import CryptoKit
import Foundation

/// Pushbullet end-to-end encryption: https://docs.pushbullet.com/#end-to-end-encryption
enum E2EE {
    enum Failure: Error {
        case missingUser, keyDerivation, invalidMessage, unsupportedVersion
    }

    /// PBKDF2-HMAC-SHA256, 30,000 iterations, salted with the user's iden, 256-bit key.
    static func deriveKey(password: String, salt: String) throws -> SymmetricKey {
        let saltBytes = Array(salt.utf8)
        var key = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password, password.utf8.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 30_000,
            &key, key.count
        )
        guard Int(status) == kCCSuccess else { throw Failure.keyDerivation }
        return SymmetricKey(data: key)
    }

    /// Decodes `base64("1" + tag(16) + iv(12) + ciphertext)` with AES-256-GCM.
    static func decrypt(_ base64: String, key: SymmetricKey) throws -> Data {
        guard let raw = Data(base64Encoded: base64), raw.count >= 29 else { throw Failure.invalidMessage }
        let bytes = [UInt8](raw)
        guard bytes[0] == UInt8(ascii: "1") else { throw Failure.unsupportedVersion }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: bytes[17..<29]),
            ciphertext: bytes[29...],
            tag: bytes[1..<17]
        )
        return try AES.GCM.open(box, using: key)
    }
}
