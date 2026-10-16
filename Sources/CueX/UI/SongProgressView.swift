import SwiftUI

struct SongProgressView: View {
    let progress: SongProgress?
    let isPlaying: Bool?
    let positionLabel: String?
    let usesTimecode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let progress {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isPlaying == true ? "NOW PLAYING" : "CURRENT SONG")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(progress.section.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 16)
                    Text("\(progress.percentage)%")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress.fraction)
                    .tint(isPlaying == true ? .green : .accentColor)
                    .accessibilityLabel("\(progress.section.name) progress")
                    .accessibilityValue("\(progress.percentage) percent; \(progress.remainingDescription) remaining")
                HStack(alignment: .top, spacing: 20) {
                    Text(positionLabel ?? "")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("Remaining: \(progress.remainingDescription)")
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .help("Remaining: \(progress.remainingDescription)")
                }
                .font(.caption)
            } else {
                Label(emptyTitle, systemImage: "music.note.list")
                    .font(.headline)
                Text(emptyDescription)
                    .lineLimit(2)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 80, alignment: .topLeading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .help("Musical progress updates each beat using the saved section lengths and meter map.")
    }

    private var emptyTitle: String {
        positionLabel == nil ? "Waiting for Logic position" : "No current song"
    }

    private var emptyDescription: String {
        if let positionLabel { return "\(positionLabel) · No song covers this beat." }
        if usesTimecode { return "Choose Show Bars & Beats in the sidebar to display song progress." }
        return "Song progress will appear when Logic sends its position."
    }
}
