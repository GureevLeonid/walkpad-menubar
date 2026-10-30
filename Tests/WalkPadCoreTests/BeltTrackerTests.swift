import Foundation
import Testing
@testable import WalkPadCore

private struct Frame {
    var speed: Double
    var elapsed: Int
    var distance: Int
}

/// Feeds one frame per second, returning every restore request.
private func feed(_ t: inout BeltTracker, _ frames: [Frame], clock: inout Date) -> [Double] {
    var out: [Double] = []
    for f in frames {
        if let r = t.observe(speed: f.speed, elapsed: f.elapsed, distance: f.distance, at: clock) { out.append(r) }
        clock += 1
    }
    return out
}

private func walking(_ speed: Double, from elapsed: Int, distance: Int, seconds: Int) -> [Frame] {
    (0..<seconds).map { Frame(speed: speed, elapsed: elapsed + $0, distance: distance + $0) }
}

private func frozen(_ speed: Double, at elapsed: Int, distance: Int, seconds: Int) -> [Frame] {
    Array(repeating: Frame(speed: speed, elapsed: elapsed, distance: distance), count: seconds)
}

// Shape captured from the pad: pause freezes counters at the old speed, resume drops to 1.0
// one frame before elapsed starts moving again.
@Test func restoresCruiseAfterPause() {
    var t = BeltTracker()
    var clock = Date(timeIntervalSince1970: 0)
    #expect(feed(&t, walking(3.4, from: 3000, distance: 2300, seconds: 10), clock: &clock).isEmpty)
    #expect(t.isMoving(at: clock))
    #expect(feed(&t, frozen(3.4, at: 3009, distance: 2309, seconds: 18), clock: &clock).isEmpty)
    #expect(t.isPaused)
    #expect(!t.isMoving(at: clock))
    #expect(feed(&t, [Frame(speed: 1.0, elapsed: 3009, distance: 2309)], clock: &clock) == [3.4])
    #expect(!t.isPaused)
    #expect(feed(&t, walking(1.0, from: 3010, distance: 2310, seconds: 2), clock: &clock).isEmpty)
    #expect(t.isMoving(at: clock))
}

@Test func noRestoreAfterCountersReset() {
    var t = BeltTracker()
    var clock = Date(timeIntervalSince1970: 0)
    _ = feed(&t, walking(3.0, from: 500, distance: 500, seconds: 6), clock: &clock)
    _ = feed(&t, frozen(3.0, at: 505, distance: 505, seconds: 5), clock: &clock)
    #expect(feed(&t, [Frame(speed: 1.0, elapsed: 0, distance: 0)], clock: &clock).isEmpty)
}

@Test func rampIsNotCruise() {
    var t = BeltTracker()
    var clock = Date(timeIntervalSince1970: 0)
    let ramp = [1.0, 1.5, 2.0, 2.5].enumerated().map { Frame(speed: $1, elapsed: $0, distance: $0) }
    _ = feed(&t, ramp, clock: &clock)
    #expect(t.cruise == nil)
}

@Test func userSetCountsImmediately() {
    var t = BeltTracker()
    var clock = Date(timeIntervalSince1970: 0)
    _ = feed(&t, walking(2.0, from: 10, distance: 10, seconds: 5), clock: &clock)
    t.userSet(3.2, at: clock)
    // Pad still reports the old speed when the user pauses right away.
    _ = feed(&t, frozen(2.0, at: 14, distance: 14, seconds: 4), clock: &clock)
    #expect(feed(&t, [Frame(speed: 1.0, elapsed: 14, distance: 14)], clock: &clock) == [3.2])
}

@Test func noRestoreWhenAlreadyAtCruise() {
    var t = BeltTracker()
    var clock = Date(timeIntervalSince1970: 0)
    _ = feed(&t, walking(1.0, from: 10, distance: 10, seconds: 5), clock: &clock)
    _ = feed(&t, frozen(1.0, at: 14, distance: 14, seconds: 4), clock: &clock)
    #expect(feed(&t, walking(1.0, from: 15, distance: 15, seconds: 1), clock: &clock).isEmpty)
    #expect(!t.isPaused)
}

@Test func launchedWhilePausedIsNotMoving() {
    var t = BeltTracker()
    var clock = Date(timeIntervalSince1970: 0)
    #expect(feed(&t, frozen(3.4, at: 3013, distance: 2330, seconds: 5), clock: &clock).isEmpty)
    #expect(!t.isMoving(at: clock))
}

// Main 2ACD frames recorded from the pad (seconds since 12:17:25): walking at 3.4 km/h, paused from
// the app at ~13 s, resumed at ~31 s, pad restarted at 1.0 km/h at 34.5 s.
private let recordedPause: [(TimeInterval, String)] = [
    (0.6, "8c 05 54 01 10 09 00 3c 00 00 00 a3 00 ff ff ff 00 b8 0b"),
    (1.5, "8c 05 54 01 10 09 00 3c 00 00 00 a3 00 ff ff ff 00 b9 0b"),
    (2.6, "8c 05 54 01 10 09 00 3c 00 00 00 a3 00 ff ff ff 00 ba 0b"),
    (3.6, "8c 05 54 01 10 09 00 3c 00 00 00 a3 00 ff ff ff 00 bb 0b"),
    (4.5, "8c 05 54 01 10 09 00 3c 00 00 00 a3 00 ff ff ff 00 bc 0b"),
    (5.5, "8c 05 54 01 10 09 00 3c 00 00 00 a3 00 ff ff ff 00 bd 0b"),
    (6.6, "8c 05 54 01 1a 09 00 3c 00 00 00 a3 00 ff ff ff 00 be 0b"),
    (7.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 bf 0b"),
    (8.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c0 0b"),
    (9.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c1 0b"),
    (10.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c2 0b"),
    (11.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c3 0b"),
    (12.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c4 0b"),
    (13.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (14.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (15.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (16.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (17.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (18.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (19.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (20.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (21.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (22.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (23.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (24.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (25.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (26.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (27.5, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (28.6, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (29.6, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (30.6, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (31.6, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (32.6, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (33.6, "8c 05 54 01 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (34.5, "8c 05 64 00 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c5 0b"),
    (35.6, "8c 05 64 00 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c6 0b"),
    (36.6, "8c 05 64 00 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c7 0b"),
    (37.5, "8c 05 64 00 1a 09 00 3c 00 00 00 a4 00 ff ff ff 00 c8 0b"),
]

@Test func replayRecordedPause() {
    var t = BeltTracker()
    let start = Date(timeIntervalSince1970: 0)
    var restores: [(TimeInterval, Double)] = []
    var pausedAt: TimeInterval?
    for (offset, hex) in recordedPause {
        let s = TreadmillDataParser.parse(Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! }))!
        if let r = t.observe(speed: s.speedKmh!, elapsed: s.elapsedSeconds, distance: s.distanceMeters,
                             at: start + offset) {
            restores.append((offset, r))
        }
        if t.isPaused, pausedAt == nil { pausedAt = offset }
    }
    #expect(t.cruise == 3.4)
    #expect(pausedAt.map { (13...17).contains($0) } == true)
    #expect(restores.count == 1)
    #expect(restores.first?.1 == 3.4)
    #expect(restores.first.map { (34...35).contains($0.0) } == true)
}
