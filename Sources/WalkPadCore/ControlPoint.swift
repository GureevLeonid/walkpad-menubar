import Foundation

/// FTMS Fitness Machine Control Point (0x2AD9) requests.
public enum FTMSCommand: Equatable, Sendable {
    case requestControl
    case setSpeed(kmh: Double)
    case setIncline(percent: Double)
    case start
    case stop
    case pause

    public var opcode: UInt8 {
        switch self {
        case .requestControl: 0x00
        case .setSpeed: 0x02
        case .setIncline: 0x03
        case .start: 0x07
        case .stop, .pause: 0x08
        }
    }

    public var bytes: Data {
        switch self {
        case .requestControl, .start: return Data([opcode])
        case .stop: return Data([opcode, 0x01])
        case .pause: return Data([opcode, 0x02])
        case .setSpeed(let kmh):
            let v = UInt16(clamping: Int((kmh * 100).rounded()))
            return Data([opcode, UInt8(v & 0xFF), UInt8(v >> 8)])
        case .setIncline(let pct):
            let v = UInt16(bitPattern: Int16(clamping: Int((pct * 10).rounded())))
            return Data([opcode, UInt8(v & 0xFF), UInt8(v >> 8)])
        }
    }
}

/// Control Point indication: `80 <request opcode> <result>`.
public struct FTMSResponse: Equatable, Sendable {
    public enum Result: UInt8, Sendable {
        case success = 0x01, notSupported = 0x02, invalidParameter = 0x03, failed = 0x04, notPermitted = 0x05
    }
    public var requestOpcode: UInt8
    public var result: Result?

    public static func parse(_ data: Data) -> FTMSResponse? {
        let b = [UInt8](data)
        guard b.count >= 3, b[0] == 0x80 else { return nil }
        return FTMSResponse(requestOpcode: b[1], result: Result(rawValue: b[2]))
    }
}

/// Supported Speed (0x2AD4) / Inclination (0x2AD5) Range: min, max, step as 3×int16.
public struct SupportedRange: Equatable, Sendable {
    public var min: Double
    public var max: Double
    public var step: Double

    public init(min: Double, max: Double, step: Double) {
        self.min = min
        self.max = max
        self.step = step
    }

    /// `scale` is the field resolution: 0.01 for speed (km/h), 0.1 for incline (%).
    public static func parse(_ data: Data, scale: Double) -> SupportedRange? {
        let b = [UInt8](data)
        guard b.count >= 6 else { return nil }
        func v(_ i: Int) -> Double { Double(Int16(bitPattern: UInt16(b[i]) | UInt16(b[i + 1]) << 8)) * scale }
        let r = SupportedRange(min: v(0), max: v(2), step: v(4))
        return r.step > 0 && r.max >= r.min ? r : nil
    }

    /// Snap to the step grid and clamp into range.
    public func clamp(_ x: Double) -> Double {
        let snapped = min + ((x - min) / step).rounded() * step
        return Swift.min(max, Swift.max(min, (snapped * 100).rounded() / 100))
    }
}
