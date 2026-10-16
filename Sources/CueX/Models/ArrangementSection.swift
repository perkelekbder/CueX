import Foundation

struct ArrangementSection: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var startTick: Int
    var lengthTicks: Int

    init(name: String, startTick: Int, lengthTicks: Int) {
        self.id = "\(startTick)|\(name.trimmingCharacters(in: .whitespacesAndNewlines))"
        self.name = name
        self.startTick = startTick
        self.lengthTicks = lengthTicks
    }
}

struct ImportedLogicProject: Hashable {
    var projectName: String
    var projectURL: URL
    var sections: [ArrangementSection]
    var timeSignatures: [TimeSignature]
    var tempoChanges: [TempoChange]
    var timecodeFrameRate: Int?

    func section(at position: MackieClockPosition) -> ArrangementSection? {
        guard let beat = MusicalTimeFormatter.beatRange(bar: position.bar, beat: position.beat, signatures: timeSignatures) else { return nil }
        // Do not extend the previous song into a gap or guess a section when a
        // boundary falls inside the displayed beat. Sub-beat tracking comes later.
        return sections.last {
            $0.startTick <= beat.lowerBound && $0.startTick + $0.lengthTicks >= beat.upperBound
        }
    }
}

struct TempoChange: Hashable {
    var startTick: Int
    var beatsPerMinute: Double
}
