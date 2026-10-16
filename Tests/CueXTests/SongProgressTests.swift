import XCTest
@testable import CueX

final class SongProgressTests: XCTestCase {
    func testStartAndRemainingAcrossMeterChange() throws {
        let start = try XCTUnwrap(SongProgress(project: project, position: position(1)))
        XCTAssertEqual(start.fraction, 0)
        XCTAssertEqual(start.remainingTicks, 13_440)
        XCTAssertEqual(start.remainingDescription, "2 bars (4/4) + 2 bars (3/4)")

        let changedMeter = try XCTUnwrap(SongProgress(project: project, position: position(3)))
        XCTAssertEqual(changedMeter.elapsedTicks, 7_680)
        XCTAssertEqual(changedMeter.remainingTicks, 5_760)
        XCTAssertEqual(changedMeter.fraction, 4.0 / 7.0, accuracy: 0.000001)
        XCTAssertEqual(changedMeter.remainingDescription, "2 bars (3/4)")
    }

    func testFinalBeatAndBackwardSeek() throws {
        let finalBeat = try XCTUnwrap(SongProgress(project: project, position: position(4, 3)))
        XCTAssertEqual(finalBeat.remainingDescription, "1 beat (3/4)")
        XCTAssertEqual(finalBeat.remainingTicks, 960)
        XCTAssertLessThan(finalBeat.percentage, 100)
        let backwards = try XCTUnwrap(SongProgress(project: project, position: position(2)))
        XCTAssertLessThan(backwards.fraction, finalBeat.fraction)
        XCTAssertGreaterThan(backwards.remainingTicks, finalBeat.remainingTicks)
    }

    func testBoundariesGapsAndZeroLengthDoNotKeepPreviousProgress() throws {
        var fixture = project
        fixture.sections = [
            ArrangementSection(name: "First", startTick: 0, lengthTicks: 3_840),
            ArrangementSection(name: "Second", startTick: 7_680, lengthTicks: 2_880),
            ArrangementSection(name: "Empty", startTick: 10_560, lengthTicks: 0)
        ]
        XCTAssertNil(SongProgress(project: fixture, position: position(2)))
        let next = try XCTUnwrap(SongProgress(project: fixture, position: position(3)))
        XCTAssertEqual(next.section.name, "Second")
        XCTAssertEqual(next.fraction, 0)
        XCTAssertNil(SongProgress(project: fixture, position: position(4)))
        XCTAssertNil(SongProgress(project: fixture, position: position(5)))
    }

    func testDivisionAndTickDoNotImplyUnsupportedPrecision() throws {
        let start = try XCTUnwrap(SongProgress(project: project, position: position(2)))
        let withinBeat = try XCTUnwrap(SongProgress(project: project, position: MackieClockPosition(bar: 2, beat: 1, division: 4, tick: 200)))
        XCTAssertEqual(start.elapsedTicks, withinBeat.elapsedTicks)
        XCTAssertEqual(start.remainingDescription, withinBeat.remainingDescription)
        XCTAssertNil(SongProgress(project: project, position: position(3, 4)))
    }

    private func position(_ bar: Int, _ beat: Int = 1) -> MackieClockPosition {
        MackieClockPosition(bar: bar, beat: beat, division: 1, tick: 1)
    }

    private var project: ImportedLogicProject {
        ImportedLogicProject(
            projectName: "Fixture", projectURL: URL(fileURLWithPath: "/tmp/fixture.logicx"),
            sections: [ArrangementSection(name: "Mixed meters", startTick: 0, lengthTicks: 13_440)],
            timeSignatures: [TimeSignature(startTick: 0, numerator: 4, denominator: 4), TimeSignature(startTick: 7_680, numerator: 3, denominator: 4)],
            tempoChanges: [], timecodeFrameRate: 25
        )
    }
}
