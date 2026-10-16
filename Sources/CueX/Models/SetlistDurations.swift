import Foundation

/// Integrate each song independently on Logic's tempo timeline. CueX order
/// doesn't change its duration, and space between sections is never included.
struct SetlistDurations {
    let songSeconds: [String: Double]
    let totalSeconds: Double?

    init(project: ImportedLogicProject) {
        var durations: [String: Double] = [:]
        var total = 0.0
        var complete = true
        for section in project.sections {
            let (end, overflow) = section.startTick.addingReportingOverflow(section.lengthTicks)
            guard !overflow, section.lengthTicks >= 0,
                  let seconds = MusicalTimeline.seconds(from: section.startTick, to: end, tempos: project.tempoChanges),
                  seconds.isFinite, seconds >= 0 else {
                complete = false
                continue
            }
            durations[section.id] = seconds
            total += seconds
        }
        songSeconds = durations
        // Round only for display, after adding the unrounded song durations.
        totalSeconds = complete && total.isFinite ? total : nil
    }
}

enum ClockDurationFormatter {
    static func minutesAndSeconds(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0,
              seconds.rounded() < Double(Int.max) else { return "—" }
        let rounded = Int(seconds.rounded())
        return "\(rounded / 60):" + String(format: "%02d", rounded % 60)
    }
}
