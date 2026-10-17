import SwiftUI

struct SetTimingHeader: View {
    let model: CueXModel
    let fallbackSectionID: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = model.remainingSetSeconds(fallbackSectionID: fallbackSectionID)
            let finish = model.estimatedSetFinish(remainingSeconds: remaining, now: context.date)
            HStack(spacing: 12) {
                timingValue("Remaining", value: ClockDurationFormatter.string(remaining))
                    .help("Remaining song and pause time up to the first full stop. Excludes timeline gaps, manual waits, and transition delays. Remaining follows Logic’s reported beat; without a position it starts from the selected song.")
                timingValue(finishLabel, value: ClockDurationFormatter.clockTime(finish))
                .help(finish.map {
                    $0.formatted(date: .abbreviated, time: .shortened)
                        + (model.playlistAutomation.setFinishedAt == nil
                           ? "\nEstimate assuming no additional pauses. While stopped, assumes starting or resuming now."
                           : "\nLogic confirmed the final automatic stop.")
                } ?? "Finish time unavailable until usable tempo and position feedback are available.")
            }
            .lineLimit(1)
        }
        .frame(height: 72)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(LogicTheme.timing)
    }

    private func timingValue(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(LogicTheme.secondaryText)
            Text(value)
                .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var finishLabel: String {
        if model.playlistAutomation.setFinishedAt != nil { return "Finished" }
        return model.midiController.isPlaying == true || model.playlistAutomation.pauseSectionID != nil
            ? "Est. finish" : "Finish if resumed now"
    }
}
