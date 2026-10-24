import CryptoKit
import Foundation
import Testing
@testable import PushbulletTray

/// Test vectors from https://docs.pushbullet.com/#end-to-end-encryption
struct E2EETests {
    let key = SymmetricKey(data: Data(base64Encoded: "1sW28zp7CWv5TtGjlQpDHHG4Cbr9v36fG5o4f74LsKg=")!)

    @Test func derivesDocumentedKey() throws {
        let derived = try E2EE.deriveKey(password: "hunter2", salt: "up0snaKOsn")
        #expect(derived == key)
    }

    @Test func decryptsDocumentedMessage() throws {
        let plaintext = try E2EE.decrypt("MSfJxxY5YdjttlfUkCaKA57qU9SuCN8+ZhYg/xieI+lDnQ==", key: key)
        #expect(String(decoding: plaintext, as: UTF8.self) == "meow!")
    }

    @Test func decryptsDocumentedEphemeral() throws {
        let ciphertext = "MXAdvN64uXWtLXCRaqYHEtGhiogR1VHyXX21Lpjp4jv3v+JWygMBA9Wp5npbQdfeZAgOZI+JT3y3pbmq+OrKXrK1rg=="
        let plaintext = try E2EE.decrypt(ciphertext, key: key)
        let json = try JSONSerialization.jsonObject(with: plaintext) as? [String: String]
        #expect(json == ["key1": "value1", "key2": "value2"])
    }

    @Test func rejectsTamperedMessage() {
        #expect(throws: (any Error).self) {
            try E2EE.decrypt("MSfJxxY5YdjttlfUkCaKA57qU9SuCN8+ZhYg/xieI+lDnA==", key: key)
        }
    }
}

struct PushTests {
    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test func mirrorAndDismissalShareKey() throws {
        let mirror = try decoder.decode(Push.self, from: Data("""
            {"type":"mirror","notification_id":"-8","notification_tag":null,"package_name":"com.whatsapp",
             "source_user_iden":"u1","application_name":"WhatsApp","title":"Bob","body":"hi","icon":"abc"}
            """.utf8))
        let dismissal = try decoder.decode(Push.self, from: Data("""
            {"type":"dismissal","notification_id":"-8","notification_tag":null,"package_name":"com.whatsapp",
             "source_user_iden":"u1"}
            """.utf8))
        #expect(mirror.notificationKey == dismissal.notificationKey)
        #expect(mirror.applicationName == "WhatsApp")
    }

    @Test func updatedMirrorHasNewContent() throws {
        let first = try decoder.decode(Push.self, from: Data(#"{"type":"mirror","notification_id":"-8","title":"Bob","body":"hi"}"#.utf8))
        let again = try decoder.decode(Push.self, from: Data(#"{"type":"mirror","notification_id":"-8","title":"Bob","body":"hi"}"#.utf8))
        let updated = try decoder.decode(Push.self, from: Data(#"{"type":"mirror","notification_id":"-8","title":"Bob","body":"hi\nhow are you?"}"#.utf8))
        #expect(first.notificationKey == updated.notificationKey)
        #expect(first.hasSameContent(as: again))
        #expect(!first.hasSameContent(as: updated))
    }

    @Test func numericNotificationIdRoundTrips() throws {
        let push = try decoder.decode(Push.self, from: Data(#"{"type":"mirror","notification_id":42}"#.utf8))
        #expect(push.notificationId == .number(42))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(DismissalEphemeral(dismissing: push)), as: UTF8.self)
        #expect(json == #"{"push":{"notification_id":42,"type":"dismissal"},"type":"push"}"#)
    }

    @Test func historyPushUsesIdenAsKey() throws {
        let push = try decoder.decode(Push.self, from: Data(#"{"iden":"abc","type":"note","modified":1729700000.123456}"#.utf8))
        #expect(push.notificationKey == "abc")
        #expect("\(push.modified!)" == "1729700000.123456")
    }

    @Test func lenientDecodingKeepsOtherFields() throws {
        let push = try decoder.decode(Push.self, from: Data(#"{"type":"mirror","title":5,"body":"still here"}"#.utf8))
        #expect(push.title == nil)
        #expect(push.body == "still here")
    }

    @Test func decryptedFieldsOverrideEnvelope() throws {
        let envelope = try decoder.decode(Push.self, from: Data(#"{"encrypted":true,"ciphertext":"x"}"#.utf8))
        let inner = try decoder.decode(Push.self, from: Data(#"{"type":"mirror","title":"t"}"#.utf8))
        let merged = envelope.merging(inner)
        #expect(merged.type == "mirror")
        #expect(merged.title == "t")
        #expect(merged.ciphertext == "x")
    }
}
