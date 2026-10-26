import Foundation
import Testing
@testable import WalkPadCore

private func bytes(_ d: Data) -> [UInt8] { [UInt8](d) }

@Test func commandEncoding() {
    #expect(bytes(FTMSCommand.requestControl.bytes) == [0x00])
    // Verified on the pad: 02 fa 00 → 2.50 km/h, 02 04 01 → 2.60 km/h.
    #expect(bytes(FTMSCommand.setSpeed(kmh: 2.5).bytes) == [0x02, 0xFA, 0x00])
    #expect(bytes(FTMSCommand.setSpeed(kmh: 2.6).bytes) == [0x02, 0x04, 0x01])
    #expect(bytes(FTMSCommand.setIncline(percent: 2).bytes) == [0x03, 0x14, 0x00])
    #expect(bytes(FTMSCommand.setIncline(percent: -1).bytes) == [0x03, 0xF6, 0xFF])
    #expect(bytes(FTMSCommand.start.bytes) == [0x07])
    #expect(bytes(FTMSCommand.stop.bytes) == [0x08, 0x01])
    #expect(bytes(FTMSCommand.pause.bytes) == [0x08, 0x02])
}

@Test func responseParsing() {
    #expect(FTMSResponse.parse(Data([0x80, 0x02, 0x01])) == FTMSResponse(requestOpcode: 0x02, result: .success))
    #expect(FTMSResponse.parse(Data([0x80, 0x07, 0x05]))?.result == .notPermitted)
    #expect(FTMSResponse.parse(Data([0x02, 0x01])) == nil)
}

@Test func supportedRanges() throws {
    // Captured from the Dreaver Elevate One.
    let speed = try #require(SupportedRange.parse(Data([0x64, 0x00, 0x58, 0x02, 0x0a, 0x00]), scale: 0.01))
    #expect(speed == SupportedRange(min: 1.0, max: 6.0, step: 0.1))
    let incline = try #require(SupportedRange.parse(Data([0x00, 0x00, 0x5a, 0x00, 0x0a, 0x00]), scale: 0.1))
    #expect(incline == SupportedRange(min: 0, max: 9, step: 1))

    #expect(speed.clamp(2.6) == 2.6)
    #expect(speed.clamp(6.3) == 6.0)
    #expect(speed.clamp(0.4) == 1.0)
    #expect(incline.clamp(9.5) == 9)
    #expect(incline.clamp(2.4) == 2)
}
