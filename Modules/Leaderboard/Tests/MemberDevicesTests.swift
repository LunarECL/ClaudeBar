import Foundation
import Testing
@testable import Leaderboard

/// A member's devices as `/me` lists them (design §2a): the one that joined,
/// who is in their first week, which were added since a device, and removing one.
@Suite
struct MemberDevicesTests {
    /// Day 20: devices added on day 13 or before are past their first week.
    private let today = LeaderboardFixtures.date(20)

    private func device(_ key: String, addedOn day: Int, removedOn removed: Int? = nil) -> Device {
        Device(publicKey: DeviceKey(key), label: DeviceLabel("Mac \(key)")!, addedAt: LeaderboardFixtures.date(day),
               removedAt: removed.map { LeaderboardFixtures.date($0) })
    }

    // MARK: - The one that joined

    @Test func `should take the earliest device as the one that joined, though it was removed`() {
        let devices = MemberDevices([device("k2", addedOn: 5), device("k1", addedOn: 1, removedOn: 3)])

        #expect(devices.joined?.publicKey == DeviceKey("k1"))
    }

    // MARK: - The first week

    @Test func `should hold a device added less than a week ago to its first week`() {
        let recent = device("k2", addedOn: 17)
        let devices = MemberDevices([device("k1", addedOn: 1), recent])

        #expect(devices.isInFirstWeek(recent, at: today))
    }

    @Test func `should let a device out of its first week once a week has passed`() {
        let older = device("k2", addedOn: 13)
        let devices = MemberDevices([device("k1", addedOn: 1), older])

        #expect(!devices.isInFirstWeek(older, at: today))
    }

    @Test func `should never hold the device that joined to a first week`() {
        let joined = device("k1", addedOn: 18)
        let devices = MemberDevices([joined, device("k2", addedOn: 19)])

        #expect(!devices.isInFirstWeek(joined, at: today))
    }

    // MARK: - Added since a device

    @Test func `should list the devices in use added after a device`() {
        let me = device("k2", addedOn: 3)
        let added = device("k3", addedOn: 5)
        let devices = MemberDevices([device("k1", addedOn: 1), me, added, device("k4", addedOn: 6, removedOn: 7)])

        #expect(devices.added(since: me) == [added])
    }

    // MARK: - Changing the list

    @Test func `should say which device removed one, and when`() {
        let older = device("k2", addedOn: 5)
        let by = DeviceRef(publicKey: DeviceKey("k1"), label: DeviceLabel("MacBook Pro")!)

        let devices = MemberDevices([device("k1", addedOn: 1), older]).removing(older, by: by, at: today)

        let removed = devices.device(withKey: DeviceKey("k2"))
        #expect(removed?.removedAt == today)
        #expect(removed?.removedBy == by)
        #expect(devices.device(withKey: DeviceKey("k1"))?.isRemoved == false)
    }

    @Test func `should add a device once, however often it is added`() {
        let new = device("k2", addedOn: 19)

        let devices = MemberDevices([device("k1", addedOn: 1)]).adding(new).adding(new)

        #expect(devices.map(\.publicKey) == [DeviceKey("k1"), DeviceKey("k2")])
    }
}
