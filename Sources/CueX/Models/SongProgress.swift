import Foundation

/// A musical progress snapshot at the start of Logic's most recently reported
/// beat. No timer or outgoing locate command advances this value.
struct SongProgress {
    let section: ArrangementSection
    let elapsedTicks: Int
    let remainingTicks: Int
    let fraction: Double
    let remainingDescription: String

    var percentage: Int { Int((fraction * 100).rounded(.down)) }

    init?(project: ImportedLogicProject, position: MackieClockPosition) {
        guard let section = project.section(at: position), section.lengthTicks > 0,
              let beat = MusicalTimeFormatter.beatRange(bar: position.bar, beat: position.beat, signatures: project.timeSignatures) else { return nil }
        let elapsed = min(section.lengthTicks, max(0, beat.lowerBound - section.startTick))
        self.section = section
        elapsedTicks = elapsed
        remainingTicks = section.lengthTicks - elapsed
        fraction = Double(elapsed) / Double(section.lengthTicks)
        remainingDescription = MusicalTimeFormatter.duration(
            ticks: remainingTicks,
            startingAt: beat.lowerBound,
            signatures: project.timeSignatures
        )
    }
}
