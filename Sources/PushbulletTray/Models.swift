import Foundation

/// A push as delivered by the REST API or the stream. Every field is optional and
/// decoded leniently so one unexpected value never drops the whole push.
struct Push: Decodable, Sendable {
    var type: String?
    var iden: String?
    var applicationName: String?
    var title: String?
    var body: String?
    var icon: String?
    var notificationId: FlexibleID?
    var notificationTag: String?
    var packageName: String?
    var sourceUserIden: String?
    var dismissed: Bool?
    var encrypted: Bool?
    var ciphertext: String?
    var modified: Double?

    private enum CodingKeys: String, CodingKey {
        case type, iden, applicationName, title, body, icon, notificationId, notificationTag
        case packageName, sourceUserIden, dismissed, encrypted, ciphertext, modified
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) -> T? { try? c.decodeIfPresent(T.self, forKey: key) }
        type = value(.type)
        iden = value(.iden)
        applicationName = value(.applicationName)
        title = value(.title)
        body = value(.body)
        icon = value(.icon)
        notificationId = value(.notificationId)
        notificationTag = value(.notificationTag)
        packageName = value(.packageName)
        sourceUserIden = value(.sourceUserIden)
        dismissed = value(.dismissed)
        encrypted = value(.encrypted)
        ciphertext = value(.ciphertext)
        modified = value(.modified)
    }

    /// Fields from `other` win, like `{ ...self, ...other }`.
    func merging(_ other: Push) -> Push {
        var merged = self
        merged.type = other.type ?? type
        merged.iden = other.iden ?? iden
        merged.applicationName = other.applicationName ?? applicationName
        merged.title = other.title ?? title
        merged.body = other.body ?? body
        merged.icon = other.icon ?? icon
        merged.notificationId = other.notificationId ?? notificationId
        merged.notificationTag = other.notificationTag ?? notificationTag
        merged.packageName = other.packageName ?? packageName
        merged.sourceUserIden = other.sourceUserIden ?? sourceUserIden
        merged.dismissed = other.dismissed ?? dismissed
        merged.encrypted = other.encrypted ?? encrypted
        merged.ciphertext = other.ciphertext ?? ciphertext
        merged.modified = other.modified ?? modified
        return merged
    }

    /// Identifies a notification across the mirror, the dismissal and the local banner.
    var notificationKey: String {
        iden ?? [notificationId?.description, notificationTag, packageName, sourceUserIden]
            .map { $0 ?? "" }
            .joined(separator: "|")
    }
}

/// `notification_id` is documented as a string; accept a number too and send it back unchanged.
enum FlexibleID: Codable, Hashable, Sendable, CustomStringConvertible {
    case string(String)
    case number(Int64)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let string = try? c.decode(String.self) {
            self = .string(string)
        } else {
            self = .number(try c.decode(Int64.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let string): try c.encode(string)
        case .number(let number): try c.encode(number)
        }
    }

    var description: String {
        switch self {
        case .string(let string): string
        case .number(let number): String(number)
        }
    }
}

struct StreamEvent: Decodable {
    let type: String
    let subtype: String?
    let push: Push?
}

struct PushList: Decodable {
    let pushes: [Push]
}

struct User: Decodable {
    let iden: String
}

struct DismissalEphemeral: Encodable {
    struct Body: Encodable {
        var type = "dismissal"
        let notificationId: FlexibleID?
        let notificationTag: String?
        let packageName: String?
        let sourceUserIden: String?
    }

    var type = "push"
    let push: Body

    init(dismissing push: Push) {
        self.push = Body(
            notificationId: push.notificationId,
            notificationTag: push.notificationTag,
            packageName: push.packageName,
            sourceUserIden: push.sourceUserIden
        )
    }
}

struct APIError: LocalizedError {
    let errorDescription: String?
}
