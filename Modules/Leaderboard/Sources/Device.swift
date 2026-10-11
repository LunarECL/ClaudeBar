import Foundation

/// *DEVICE* (design §2a): one of a member's machines, which is one key. `/me`
/// lists them, removed ones included; a removed device's days stay and count.
public struct Device: Sendable, Equatable, Decodable {
    /// The key it signs with: the device, as the server knows it.
    public let publicKey: DeviceKey
    public let label: DeviceLabel
    public let addedAt: Date
    public let removedAt: Date?
    /// The device that removed it, `nil` while it's in use.
    public let removedBy: DeviceRef?

    public init(publicKey: DeviceKey, label: DeviceLabel, addedAt: Date, removedAt: Date? = nil, removedBy: DeviceRef? = nil) {
        self.publicKey = publicKey
        self.label = label
        self.addedAt = addedAt
        self.removedAt = removedAt
        self.removedBy = removedBy
    }

    public var isRemoved: Bool { removedAt != nil }

    /// This device once `by` removed it at `time`, as `/me` will list it.
    func removed(by: DeviceRef, at time: Date) -> Device {
        Device(publicKey: publicKey, label: label, addedAt: addedAt, removedAt: time, removedBy: by)
    }

    private enum CodingKeys: String, CodingKey { case publicKey, label, addedAt, removedAt, removedBy }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publicKey = try container.decode(DeviceKey.self, forKey: .publicKey)
        label = try container.decode(DeviceLabel.self, forKey: .label)
        addedAt = try ServerTime.decode(from: container, forKey: .addedAt)
        removedAt = try ServerTime.decodeIfPresent(from: container, forKey: .removedAt)
        removedBy = try container.decodeIfPresent(DeviceRef.self, forKey: .removedBy)
    }
}

/// A device named in passing: the one that removed another.
public struct DeviceRef: Sendable, Equatable, Decodable {
    public let publicKey: DeviceKey
    public let label: DeviceLabel

    public init(publicKey: DeviceKey, label: DeviceLabel) {
        self.publicKey = publicKey
        self.label = label
    }
}

/// A device, as the server knows it: the public half of the key it signs
/// with, base64url, as `X-Key` names it. Only the wire and the stored record
/// hold it as text.
public struct DeviceKey: Sendable, Hashable, Decodable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(String.self)
    }

    public var description: String { value }
}

extension SigningKey {
    /// The device this key signs as.
    public var deviceKey: DeviceKey { DeviceKey(publicKey) }
}

/// What a device is called on the member's list: the label the person typed
/// when it joined or was added, filled in with the machine's model and never
/// its computer name, which is often a person's (design §6). The server takes
/// 1–40 characters without control characters, counting them as JavaScript
/// does, in UTF-16 units: an emoji can count as several.
public struct DeviceLabel: Sendable, Hashable, Decodable, CustomStringConvertible {
    public let value: String

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(trimmed.utf16.count),
              !trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        value = trimmed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let label = DeviceLabel(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a device's label: \(text)")
        }
        self = label
    }

    public var description: String { value }
}

/// The code a new device shows until one the member has approves it: 8 of
/// RFC 8628's consonants, shown as `WDJB-MJHT` and read however it's typed.
public struct DeviceCode: Sendable, Hashable, CustomStringConvertible {
    /// The 8 letters, upper case, as the server's paths take them.
    public let value: String

    private static let alphabet = Set("BCDFGHJKLMNPQRSTVWXZ")

    public init?(_ typed: String) {
        let letters = typed.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard letters.count == 8, letters.allSatisfy(Self.alphabet.contains) else { return nil }
        value = letters
    }

    public var description: String { "\(value.prefix(4))-\(value.suffix(4))" }
}

/// What approving a code would add: the label the new device asked with, and
/// when, shown above *Approve* so a code read out to a stranger isn't
/// approved blind (RFC 8628 §5.4).
public struct PendingDevice: Sendable, Equatable, Decodable {
    public let label: DeviceLabel
    public let requestedAt: Date

    public init(label: DeviceLabel, requestedAt: Date) {
        self.label = label
        self.requestedAt = requestedAt
    }

    private enum CodingKeys: String, CodingKey { case label, requestedAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(DeviceLabel.self, forKey: .label)
        requestedAt = try ServerTime.decode(from: container, forKey: .requestedAt)
    }
}

/// The server's answer to a new device asking to be added: its code, how long
/// the code lasts and how often to ask whether it was approved.
public struct DeviceAuthorization: Sendable, Equatable {
    public let code: DeviceCode
    public let expiresIn: TimeInterval
    public let interval: TimeInterval

    public init(code: DeviceCode, expiresIn: TimeInterval, interval: TimeInterval) {
        self.code = code
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

/// Where a new device's code stands, by `GET /me` signed with its own key.
public enum DeviceApproval: Sendable, Equatable {
    /// Not approved yet: `202`, with no member data.
    case waiting
    /// Approved: the member it joined, as `/me` answers.
    case approved(MemberSummary)
}

/// A time as the server writes it: JavaScript's `toISOString()`, UTC with
/// milliseconds (§5). Read without the milliseconds too; anything else fails
/// the answer rather than guess.
enum ServerTime {
    static func decode<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Date {
        let text = try container.decode(String.self, forKey: key)
        guard let date = date(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Not a time: \(text)")
        }
        return date
    }

    static func decodeIfPresent<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Date? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else { return nil }
        return try decode(from: container, forKey: key)
    }

    private static func date(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: text) { return date }
        iso.formatOptions.remove(.withFractionalSeconds)
        return iso.date(from: text)
    }
}

/// How a device is removed, as the dialog offers it (design §2a): its key is
/// revoked either way; its days stay, or are deleted once it is removed.
public enum Removal: Sendable, Equatable, CaseIterable {
    /// *Remove*: its days stay and count until deleted.
    case keepingItsDays
    /// *Remove and delete its days*: offered only for another device in its first week.
    case deletingItsDays
}
