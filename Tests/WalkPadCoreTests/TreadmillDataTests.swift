import Foundation
import Testing
@testable import WalkPadCore

private func frame(_ hex: String) -> Data {
    Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
}

// Frames captured from a Dreaver Elevate One (firmware V2.6.3) while walking.
private let mainFrame = "8c 05 fa 00 22 0b 00 14 00 00 00 c8 00 ff ff ff 00 4a 10"
private let stepsFrame = "01 20 73 14 00"

@Test func mainFrameDecodes() {
    #expect(TreadmillDataParser.parse(frame(mainFrame)) ==
        TreadmillSample(speedKmh: 2.5, distanceMeters: 2850, inclinePercent: 2.0,
                        kcal: 200, heartRate: nil, elapsedSeconds: 4170))
}

@Test func stepsFrameDecodes() {
    #expect(TreadmillDataParser.parse(frame(stepsFrame)) == TreadmillSample(steps: 5235))
}

@Test func framesMerge() throws {
    var s = try #require(TreadmillDataParser.parse(frame(mainFrame)))
    s.merge(try #require(TreadmillDataParser.parse(frame(stepsFrame))))
    #expect(s.speedKmh == 2.5)
    #expect(s.steps == 5235)
}

@Test func truncatedFramesRejected() {
    #expect(TreadmillDataParser.parse(frame("8c 05 fa")) == nil)
    #expect(TreadmillDataParser.parse(frame("01")) == nil)
}
