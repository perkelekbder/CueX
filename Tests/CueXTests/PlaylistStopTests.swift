import XCTest
@testable import CueX

final class PlaylistStopTests: XCTestCase {
    func testLastSongIsMandatoryAndDoesNotWrap() throws {
        let project = fixture
        XCTAssertTrue(PlaylistStopPolicy.isEnabled(for: project.sections[2], in: project, savedIDs: []))
        XCTAssertFalse(PlaylistStopPolicy.isEnabled(for: project.sections[0], in: project, savedIDs: []))
        let stop = try XCTUnwrap(PlaylistStopPolicy.nextBoundary(from: 0, project: project, savedIDs: []))
        XCTAssertEqual(stop.sectionID, project.sections[2].id)
        XCTAssertEqual(stop.endTick, 11_520)
        XCTAssertNil(stop.nextSectionID)
        XCTAssertEqual(PlaylistStopPolicy.nextBoundary(from: 99_999, project: project, savedIDs: [])?.sectionID, stop.sectionID)
    }

    func testProgrammedStopsSkipUncheckedSongs() throws {
        let project = fixture
        let enabled: Set<String> = [project.sections[0].id]
        let first = try XCTUnwrap(PlaylistStopPolicy.nextBoundary(from: 3_000, project: project, savedIDs: enabled))
        XCTAssertEqual(first.sectionID, project.sections[0].id)
        XCTAssertEqual(first.nextSectionID, project.sections[1].id)
        let later = try XCTUnwrap(PlaylistStopPolicy.nextBoundary(from: 4_000, project: project, savedIDs: enabled))
        XCTAssertEqual(later.sectionID, project.sections[2].id)
    }

    func testNextSongCannotArmBeforeStopAcknowledgement() throws {
        let target = try XCTUnwrap(PlaylistStopPolicy.nextBoundary(from: 0, project: fixture, savedIDs: [fixture.sections[0].id]))
        var transition = PlaylistStopTransition()
        XCTAssertTrue(transition.request(target, armNext: true))
        XCTAssertFalse(transition.request(target, armNext: true))
        XCTAssertNil(transition.acknowledge(isPlaying: true))
        XCTAssertNil(transition.acknowledge(isPlaying: nil))
        let completed = try XCTUnwrap(transition.acknowledge(isPlaying: false))
        XCTAssertTrue(completed.armNext)
        XCTAssertEqual(completed.boundary.nextSectionID, fixture.sections[1].id)
        XCTAssertNil(transition.acknowledge(isPlaying: false))
        XCTAssertTrue(transition.request(target, armNext: false))
        XCTAssertFalse(try XCTUnwrap(transition.acknowledge(isPlaying: false)).armNext)
    }

    func testManualOverrideCancelsPendingAutomaticArm() throws {
        var transition = PlaylistStopTransition()
        let target = try XCTUnwrap(PlaylistStopPolicy.nextBoundary(from: 0, project: fixture, savedIDs: []))
        XCTAssertTrue(transition.request(target, armNext: true))
        transition.reset()
        XCTAssertNil(transition.acknowledge(isPlaying: false))
    }

    func testTimelineIncludesTempoChanges() throws {
        let tempos = [TempoChange(startTick: 0, beatsPerMinute: 120), TempoChange(startTick: 960, beatsPerMinute: 60)]
        XCTAssertEqual(try XCTUnwrap(MusicalTimeline.seconds(from: 480, to: 1_920, tempos: tempos)), 1.25, accuracy: 0.000001)
        XCTAssertEqual(MusicalTimeline.seconds(from: 960, to: 960, tempos: tempos), 0)
        XCTAssertNil(MusicalTimeline.seconds(from: 0, to: 960, tempos: []))
    }

    func testNotesAndStopsPreserveEachOtherAndLoadLegacyFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OperatorNotesStore(baseDirectory: directory)
        let url = URL(fileURLWithPath: "/tmp/test-playlist.logicx")
        try store.save(["first": "Watch conductor"], for: url)
        try store.saveStopAfterSongIDs(["first"], for: url)
        XCTAssertEqual(try store.load(for: url)["first"], "Watch conductor")
        try store.save(["first": "New note"], for: url)
        XCTAssertEqual(try store.loadStopAfterSongIDs(for: url), ["first"])

        let folder = directory.appendingPathComponent("CueX/Projects")
        let saved = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: saved)) as? [String: Any])
        legacy.removeValue(forKey: "stopAfterSongIDs")
        try JSONSerialization.data(withJSONObject: legacy).write(to: saved)
        XCTAssertEqual(try store.loadStopAfterSongIDs(for: url), [])
        XCTAssertEqual(try store.load(for: url)["first"], "New note")
    }

    private var fixture: ImportedLogicProject {
        ImportedLogicProject(projectName: "Fixture", projectURL: URL(fileURLWithPath: "/tmp/fixture.logicx"),
            sections: (0..<3).map { ArrangementSection(name: "Song \($0 + 1)", startTick: $0 * 3_840, lengthTicks: 3_840) },
            timeSignatures: [TimeSignature(startTick: 0, numerator: 4, denominator: 4)],
            tempoChanges: [TempoChange(startTick: 0, beatsPerMinute: 120)], timecodeFrameRate: 25)
    }
}
