import Foundation

struct PlaylistStopBoundary: Equatable {
    let sectionID: String
    let sectionName: String
    let endTick: Int
    let nextSectionID: String?
    var continuesAutomatically = false
}

enum PlaylistStopPolicy {
    static func isEnabled(for section: ArrangementSection, in project: ImportedLogicProject, savedIDs: Set<String>) -> Bool {
        section.id == project.sections.last?.id || savedIDs.contains(section.id)
    }

    static func nextBoundary(from tick: Int, project: ImportedLogicProject, savedIDs: Set<String>) -> PlaylistStopBoundary? {
        // Find the physical song first, then follow CueX order only while the
        // next song starts exactly where the current one ends in Logic.
        let physical = project.sections.sorted { $0.startTick < $1.startTick }
        guard let current = physical.last(where: { $0.startTick <= tick && $0.startTick + $0.lengthTicks > tick })
                ?? physical.first(where: { $0.startTick > tick })
                ?? physical.last,
              var index = project.sections.firstIndex(where: { $0.id == current.id }) else { return nil }
        while true {
            let section = project.sections[index]
            let stop = isEnabled(for: section, in: project, savedIDs: savedIDs)
            let nextIndex = index + 1
            let contiguous = project.sections.indices.contains(nextIndex)
                && project.sections[nextIndex].startTick == section.startTick + section.lengthTicks
            if stop || !contiguous {
                var result = boundary(index: index, project: project)
                result.continuesAutomatically = !stop && result.nextSectionID != nil
                return result
            }
            index = nextIndex
        }
    }

    private static func boundary(index: Int, project: ImportedLogicProject) -> PlaylistStopBoundary {
        let section = project.sections[index]
        let next = project.sections.indices.contains(index + 1) ? project.sections[index + 1].id : nil
        return PlaylistStopBoundary(sectionID: section.id, sectionName: section.name,
                                    endTick: section.startTick + section.lengthTicks, nextSectionID: next)
    }
}

/// Tracks the acknowledgement separately from issuing Stop. No locate may be
/// sent until Logic reports stopped, and duplicate feedback cannot re-arm a song.
struct PlaylistStopTransition {
    private(set) var pending: PlaylistStopBoundary?
    private(set) var shouldArmNext = false

    mutating func request(_ boundary: PlaylistStopBoundary, armNext: Bool) -> Bool {
        guard pending == nil else { return false }
        pending = boundary
        shouldArmNext = armNext
        return true
    }

    mutating func acknowledge(isPlaying: Bool?) -> (boundary: PlaylistStopBoundary, armNext: Bool)? {
        guard isPlaying == false, let pending else { return nil }
        let completion = (pending, shouldArmNext)
        reset()
        return completion
    }

    mutating func reset() {
        pending = nil
        shouldArmNext = false
    }
}

enum MusicalTimeline {
    static func seconds(from start: Int, to end: Int, tempos: [TempoChange]) -> Double? {
        guard start >= 0, end >= start,
              let initial = tempos.last(where: { $0.startTick <= start }), initial.beatsPerMinute > 0 else { return nil }
        var cursor = start
        var bpm = initial.beatsPerMinute
        var seconds = 0.0
        for change in tempos where change.startTick > start && change.startTick < end {
            guard change.beatsPerMinute > 0 else { return nil }
            seconds += Double(change.startTick - cursor) / 960 * 60 / bpm
            cursor = change.startTick
            bpm = change.beatsPerMinute
        }
        seconds += Double(end - cursor) / 960 * 60 / bpm
        return seconds
    }
}
