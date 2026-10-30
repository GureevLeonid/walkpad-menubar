import Foundation

/// Works out whether the belt is moving and restores the walking ("cruise") speed after a pause.
///
/// The Dreaver pad does not report speed 0 while paused: it keeps sending the last speed with the
/// elapsed-time, distance and step counters frozen. So movement is judged by the elapsed counter
/// advancing. On resume the pad restarts at its minimum speed with the counters intact, which is
/// what distinguishes a resume from a fresh session.
public struct BeltTracker: Sendable {
    /// How long a reading must hold to count as cruise speed; filters out ramp up/down.
    public static let settleTime: TimeInterval = 3
    /// No elapsed-time progress for this long means paused (frames arrive at ~1 Hz).
    public static let stallTime: TimeInterval = 2.5

    public private(set) var cruise: Double?
    /// Belt halted mid-session (counters frozen); cleared on resume.
    public var isPaused: Bool { pausedAtDistance != nil }

    private var candidate: (speed: Double, since: Date)?
    private var lastElapsed: Int?
    private var lastProgress: Date?
    private var lastSpeed: Double?
    private var pausedAtDistance: Int?
    private var userSetAt: Date?

    public init() {}

    public func isMoving(at now: Date) -> Bool {
        guard !isPaused, let p = lastProgress, (lastSpeed ?? 0) > 0 else { return false }
        return now.timeIntervalSince(p) < Self.stallTime
    }

    /// The user picked a speed explicitly; trust it without waiting for it to settle, and don't let
    /// the pad's not-yet-updated readings overwrite it meanwhile.
    public mutating func userSet(_ speed: Double, at now: Date = Date()) {
        cruise = speed
        candidate = nil
        userSetAt = now
    }

    /// Feed every frame that carries speed. Returns a speed to restore when the belt has just resumed.
    public mutating func observe(speed: Double, elapsed: Int?, distance: Int?, at now: Date) -> Double? {
        let advanced = elapsed != nil && lastElapsed != nil && elapsed != lastElapsed
        let speedChanged = lastSpeed != nil && speed != lastSpeed
        if let elapsed { lastElapsed = elapsed }
        if advanced { lastProgress = now }
        lastSpeed = speed

        if let stop = pausedAtDistance {
            // Resume shows up as the speed dropping to the pad's start speed, a frame before
            // the counters move again.
            guard speed > 0, advanced || speedChanged else { return nil }
            pausedAtDistance = nil
            lastProgress = now
            candidate = nil
            if let c = cruise, (distance ?? 0) >= stop, abs(c - speed) >= 0.05 { return c }
            return nil
        }

        guard isMoving(at: now) else {
            if lastProgress != nil {
                pausedAtDistance = distance ?? 0
                candidate = nil
            }
            return nil
        }

        if let u = userSetAt, now.timeIntervalSince(u) < Self.settleTime, speed != cruise { return nil }
        if let c = candidate, c.speed == speed {
            if now.timeIntervalSince(c.since) >= Self.settleTime { cruise = speed }
        } else {
            candidate = (speed, now)
        }
        return nil
    }
}
