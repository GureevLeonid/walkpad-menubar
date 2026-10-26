import Foundation

/// One decoded FTMS Treadmill Data (0x2ACD) notification. Fields absent from the frame are nil.
public struct TreadmillSample: Equatable, Sendable {
    public var speedKmh: Double?
    public var distanceMeters: Int?
    public var inclinePercent: Double?
    public var kcal: Int?
    public var heartRate: Int?
    public var elapsedSeconds: Int?
    public var steps: Int?

    public init(speedKmh: Double? = nil, distanceMeters: Int? = nil, inclinePercent: Double? = nil,
                kcal: Int? = nil, heartRate: Int? = nil, elapsedSeconds: Int? = nil, steps: Int? = nil) {
        self.speedKmh = speedKmh
        self.distanceMeters = distanceMeters
        self.inclinePercent = inclinePercent
        self.kcal = kcal
        self.heartRate = heartRate
        self.elapsedSeconds = elapsedSeconds
        self.steps = steps
    }

    /// Overlay the fields present in `other` onto this sample.
    public mutating func merge(_ other: TreadmillSample) {
        if let v = other.speedKmh { speedKmh = v }
        if let v = other.distanceMeters { distanceMeters = v }
        if let v = other.inclinePercent { inclinePercent = v }
        if let v = other.kcal { kcal = v }
        if let v = other.heartRate { heartRate = v }
        if let v = other.elapsedSeconds { elapsedSeconds = v }
        if let v = other.steps { steps = v }
    }
}

/// Decoder for the FTMS Treadmill Data characteristic, tolerant of the Dreaver/FitShow quirks:
/// - flag bit 13 (reserved in the spec) carries a uint24 step counter;
/// - the firmware pads an extra byte after Inclination/Ramp Angle, so trailing fields
///   (energy, HR, MET, time, power, steps) are read backwards from the end of the frame.
public enum TreadmillDataParser {
    public static func parse(_ data: Data) -> TreadmillSample? {
        let b = [UInt8](data)
        guard b.count >= 2 else { return nil }
        let flags = UInt16(b[0]) | UInt16(b[1]) << 8
        func has(_ bit: UInt16) -> Bool { flags & bit != 0 }
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        func s16(_ i: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(i)))) }
        func u24(_ i: Int) -> Int { u16(i) | Int(b[i + 2]) << 16 }

        var s = TreadmillSample()

        // Leading fields, in spec order.
        var i = 2
        func take(_ n: Int) -> Int? {
            guard i + n <= b.count else { return nil }
            defer { i += n }
            return i
        }
        if !has(0x0001) { guard let at = take(2) else { return nil }; s.speedKmh = Double(u16(at)) / 100 }
        if has(0x0002) { guard take(2) != nil else { return nil } }               // average speed
        if has(0x0004) { guard let at = take(3) else { return nil }; s.distanceMeters = u24(at) }
        if has(0x0008) { guard let at = take(4) else { return nil }; s.inclinePercent = Double(s16(at)) / 10 }
        if has(0x0010) { guard take(4) != nil else { return nil } }               // elevation gain
        if has(0x0020) { guard take(1) != nil else { return nil } }               // instantaneous pace
        if has(0x0040) { guard take(1) != nil else { return nil } }               // average pace

        // Trailing fields, anchored at the end of the frame.
        var tail = 0
        if has(0x0080) { tail += 5 }   // total/hourly/minute energy
        if has(0x0100) { tail += 1 }   // heart rate
        if has(0x0200) { tail += 1 }   // MET
        if has(0x0400) { tail += 2 }   // elapsed time
        if has(0x0800) { tail += 2 }   // remaining time
        if has(0x1000) { tail += 4 }   // force on belt + power
        if has(0x2000) { tail += 3 }   // steps (vendor)
        var j = b.count - tail
        guard j >= i else { return nil }

        if has(0x0080) {
            let total = u16(j)
            if total != 0xFFFF { s.kcal = total }
            j += 5
        }
        if has(0x0100) { if b[j] != 0 { s.heartRate = Int(b[j]) }; j += 1 }
        if has(0x0200) { j += 1 }
        if has(0x0400) { s.elapsedSeconds = u16(j); j += 2 }
        if has(0x0800) { j += 2 }
        if has(0x1000) { j += 4 }
        if has(0x2000) { s.steps = u24(j); j += 3 }
        return s
    }
}
