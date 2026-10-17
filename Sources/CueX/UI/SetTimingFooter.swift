import SwiftUI

struct SetTimingFooter: View {
    let model: CueXModel
    let fallbackSectionID: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = model.remainingSetSeconds(fallbackSectionID: fallbackSectionID)
            let finish = model.estimatedSetFinish(remainingSeconds: remaining, now: context.date)
            VStack(spacing: 5) {
                HStack {
                    Text("Set \(model.setlistDurationLabel)")
                    Spacer(minLength: 8)
                    Text("Remaining \(ClockDurationFormatter.string(remaining))")
                }
                .monospacedDigit()
                .help("Total and remaining song time in CueX order. Excludes gaps, waits at stops, and transition delays. Remaining follows Logic’s reported beat; without a position it starts from the selected song.")
                HStack {
                    Text(finishLabel)
                    Spacer(minLength: 8)
                    Text(ClockDurationFormatter.clockTime(finish))
                        .monospacedDigit()
                }
                .help(finish.map {
                    $0.formatted(date: .abbreviated, time: .shortened)
                        + (model.playlistAutomation.setFinishedAt == nil
                           ? "\nEstimate assuming no additional pauses. While stopped, assumes starting or resuming now."
                           : "\nLogic confirmed the final automatic stop.")
                } ?? "Finish time unavailable until usable tempo and position feedback are available.")
            }
            .font(.caption2)
            .lineLimit(1)
        }
    }

    private var finishLabel: String {
        if model.playlistAutomation.setFinishedAt != nil { return "Finished" }
        return model.midiController.isPlaying == true ? "Est. finish" : "Finish if resumed now"
    }
}
