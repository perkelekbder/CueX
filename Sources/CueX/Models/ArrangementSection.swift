import Foundation

struct ArrangementSection: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var startTick: Int
    var lengthTicks: Int
    // Custom entries have no position on Logic's timeline.
    var block: SetlistBlock?

    var isSong: Bool { block == nil }
    var isFullStop: Bool { block?.kind == .fullStop }

    init(block: SetlistBlock) {
        id = "block|" + UUID().uuidString
        name = block.kind == .pause ? "Pause" : "Full stop"
        startTick = 0
        lengthTicks = 0
        self.block = block
    }

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

    var songs: [ArrangementSection] { sections.filter(\.isSong) }
    var playableEntries: [ArrangementSection] { Array(sections.prefix { !$0.isFullStop }) }

    func isExcluded(_ id: String) -> Bool {
        guard let stop = sections.firstIndex(where: \.isFullStop),
              let index = sections.firstIndex(where: { $0.id == id }) else { return false }
        return index > stop
    }

    func canCue(_ section: ArrangementSection) -> Bool {
        !section.isFullStop && !isExcluded(section.id)
    }

    func section(at position: MackieClockPosition) -> ArrangementSection? {
        guard let beat = MusicalTimeFormatter.beatRange(bar: position.bar, beat: position.beat, signatures: timeSignatures) else { return nil }
        // Do not extend the previous song into a gap or guess a section when a
        // boundary falls inside the displayed beat. Sub-beat tracking comes later.
        return songs.last {
            $0.startTick <= beat.lowerBound && $0.startTick + $0.lengthTicks >= beat.upperBound
        }
    }
}

struct TempoChange: Hashable {
    var startTick: Int
    var beatsPerMinute: Double
}

struct SetlistBlock: Hashable, Codable {
    enum Kind: String, Codable { case pause, fullStop }
    var kind: Kind
    var seconds: Int

    var isValid: Bool {
        kind == .fullStop ? seconds == 0 : (1...86_400).contains(seconds)
    }
}
