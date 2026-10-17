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
    static func string(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0,
              seconds.rounded() < Double(Int.max) else { return "—" }
        let rounded = Int(seconds.rounded())
        if rounded >= 3_600 {
            return String(format: "%02d", rounded / 3_600) + ":"
                + String(format: "%02d:%02d", (rounded / 60) % 60, rounded % 60)
        }
        return String(format: "%02d:%02d", rounded / 60, rounded % 60)
    }

    static func clockTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return "—" }
        return String(format: "%02d:%02d", hour, minute)
    }
}
