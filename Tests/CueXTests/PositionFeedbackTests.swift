import XCTest
@testable import CueX

final class PositionFeedbackTests: XCTestCase {
    func testRecordedLogicClockAndPartialUpdate() {
        var decoder = MackiePositionDecoder()
        // Captured from Logic at 17 / 1 / 3 / 156, CC 0x49 down to 0x40.
        let captured: [UInt8] = [32, 49, 55, 32, 49, 32, 51, 49, 53, 54]
        for (offset, value) in captured.enumerated() {
            decoder.consume(.display(index: 9 - offset, value: value))
        }
        XCTAssertNil(decoder.position, "Don't interpret digits without the Beats LED")
        decoder.consume(.note(number: 0x72, value: 127))
        XCTAssertEqual(decoder.position, MackieClockPosition(bar: 17, beat: 1, division: 3, tick: 156))

        for (index, value): (Int, UInt8) in [(7, 56), (3, 49), (2, 32), (1, 32), (0, 49)] {
            decoder.consume(.display(index: index, value: value))
        }
        XCTAssertEqual(decoder.position, MackieClockPosition(bar: 18, beat: 1, division: 1, tick: 1))
    }

    func testIncompleteAndTimecodeDisplaysDoNotProduceMusicalPosition() {
        var decoder = MackiePositionDecoder()
        decoder.consume(.note(number: 0x72, value: 127))
        decoder.consume(.display(index: 0, value: 49))
        XCTAssertNil(decoder.position)
        for (offset, value) in Array("  1 1 1  1".utf8).enumerated() {
            decoder.consume(.display(index: 9 - offset, value: value | 0x40))
        }
        XCTAssertEqual(decoder.position?.bar, 1, "Decimal-point flags must not corrupt digits")
        decoder.consume(.note(number: 0x71, value: 127))
        XCTAssertNil(decoder.position, "SMPTE digits are not bars and beats")
    }

    func testMeterChangesResolveBeatRanges() {
        XCTAssertEqual(MusicalTimeFormatter.beatRange(bar: 3, beat: 2, signatures: meters), 8_640..<9_600)
        XCTAssertEqual(MusicalTimeFormatter.beatRange(bar: 5, beat: 7, signatures: meters), 16_320..<16_800)
        XCTAssertNil(MusicalTimeFormatter.beatRange(bar: 4, beat: 4, signatures: meters))
        XCTAssertNil(MusicalTimeFormatter.beatRange(bar: 0, beat: 1, signatures: meters))
    }

    func testSectionBoundariesGapsAndEndOfSetlist() {
        let sections = [
            ArrangementSection(name: "First", startTick: 0, lengthTicks: 7_680),
            ArrangementSection(name: "Second", startTick: 7_680, lengthTicks: 2_880),
            ArrangementSection(name: "Third", startTick: 13_440, lengthTicks: 3_360)
        ]
        let project = ImportedLogicProject(projectName: "Fixture", projectURL: URL(fileURLWithPath: "/tmp/fixture.logicx"), sections: sections, timeSignatures: meters, tempoChanges: [], timecodeFrameRate: 25)
        func position(_ bar: Int, _ beat: Int = 1) -> MackieClockPosition {
            MackieClockPosition(bar: bar, beat: beat, division: 1, tick: 1)
        }
        XCTAssertEqual(project.section(at: position(2))?.name, "First")
        XCTAssertEqual(project.section(at: position(3))?.name, "Second")
        XCTAssertNil(project.section(at: position(4)), "Gaps must not inherit the previous song")
        XCTAssertEqual(project.section(at: position(5, 7))?.name, "Third")
        XCTAssertNil(project.section(at: position(6)), "End positions are exclusive")
    }

    private var meters: [TimeSignature] {
        [TimeSignature(startTick: 0, numerator: 4, denominator: 4),
         TimeSignature(startTick: 7_680, numerator: 3, denominator: 4),
         TimeSignature(startTick: 13_440, numerator: 7, denominator: 8)]
    }
}
