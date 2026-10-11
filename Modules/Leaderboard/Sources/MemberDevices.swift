import Foundation

/// *DEVICES* (design §2a): a member's devices as `/me` last listed them,
/// removed ones included. It owns the rules about them: which one joined, who
/// is still in their first week, and which were added since a device. A device
/// in its own first week reads only itself, so it asks these about others only.
public struct MemberDevices: Sendable, Equatable, RandomAccessCollection {
    /// A device added less than this long ago can't yet act for the member.
    static let firstWeek: TimeInterval = 7 * 24 * 60 * 60

    private let devices: [Device]

    public init(_ devices: [Device] = []) {
        self.devices = devices
    }

    public var startIndex: Int { devices.startIndex }
    public var endIndex: Int { devices.endIndex }
    public subscript(position: Int) -> Device { devices[position] }

    /// The device that joined: the member's earliest, since every other one
    /// was added after it. Removed or not, `/me` still lists it.
    public var joined: Device? {
        devices.min { $0.addedAt < $1.addedAt }
    }

    public func device(withKey publicKey: DeviceKey) -> Device? {
        devices.first { $0.publicKey == publicKey }
    }

    /// Added less than a week before `now`. The device that joined is the
    /// member, so it is never held to a first week.
    public func isInFirstWeek(_ device: Device, at now: Date) -> Bool {
        device.publicKey != joined?.publicKey && now.timeIntervalSince(device.addedAt) < Self.firstWeek
    }

    /// The devices still in use that were added after `device`: news to it.
    public func added(since device: Device) -> [Device] {
        devices.filter { !$0.isRemoved && $0.publicKey != device.publicKey && $0.addedAt > device.addedAt }
    }

    /// These devices once `by` removed `device` at `time`.
    public func removing(_ device: Device, by: DeviceRef, at time: Date) -> MemberDevices {
        MemberDevices(devices.map { $0.publicKey == device.publicKey ? $0.removed(by: by, at: time) : $0 })
    }

    /// These devices with `device`, unless it is already listed.
    public func adding(_ device: Device) -> MemberDevices {
        self.device(withKey: device.publicKey) == nil ? MemberDevices(devices + [device]) : self
    }
}
