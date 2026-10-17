import Foundation

enum RemainingSetTime {
    static func seconds(project: ImportedLogicProject, durations: SetlistDurations,
                        position: MackieClockPosition?, fallbackSectionID: String?) -> Double? {
        guard durations.totalSeconds != nil else { return nil }
        guard !project.sections.isEmpty else { return 0 }
        if let position {
            guard let beat = MusicalTimeFormatter.beatRange(bar: position.bar, beat: position.beat,
                                                          signatures: project.timeSignatures) else { return nil }
            if let current = project.section(at: position),
               let index = project.sections.firstIndex(where: { $0.id == current.id }) {
                if project.isExcluded(current.id) { return 0 }
                guard let songRemaining = MusicalTimeline.seconds(from: max(current.startTick, beat.lowerBound),
                    to: current.startTick + current.lengthTicks, tempos: project.tempoChanges),
                      let later = sum(from: index + 1, project: project, durations: durations) else { return nil }
                return songRemaining + later
            }
            // Don't guess which song owns a beat crossing a sub-beat boundary.
            if project.songs.contains(where: {
                $0.startTick < beat.upperBound && $0.startTick + $0.lengthTicks > beat.lowerBound
            }) { return nil }
            // In a timeline gap, count the songs after the one just passed in
            // CueX order, even if their Logic positions are earlier in the project.
            if let previous = project.songs.filter({ $0.startTick + $0.lengthTicks <= beat.lowerBound })
                .max(by: { $0.startTick + $0.lengthTicks < $1.startTick + $1.lengthTicks }),
               let index = project.sections.firstIndex(where: { $0.id == previous.id }) {
                return sum(from: index + 1, project: project, durations: durations)
            }
        }
        let startIndex = project.sections.firstIndex(where: { $0.id == fallbackSectionID }) ?? 0
        return sum(from: startIndex, project: project, durations: durations)
    }

    static func sum(from index: Int, project: ImportedLogicProject, durations: SetlistDurations) -> Double? {
        var total = 0.0
        for section in project.sections.dropFirst(index) {
            if section.isFullStop || project.isExcluded(section.id) { break }
            guard let seconds = durations.songSeconds[section.id] else { return nil }
            total += seconds
        }
        return total.isFinite ? total : nil
    }
}
