import SwiftUI

struct LogicConnectionIndicator: View {
    let midi: LogicMIDIController
    @State private var showsDetails = false

    var body: some View {
        Button { showsDetails.toggle() } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(midi.connectionHealth.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "info.circle").foregroundStyle(LogicTheme.secondaryText)
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(midi.connectionHealth.explanation)
        .accessibilityLabel("Logic connection: \(midi.connectionHealth.label)")
        .popover(isPresented: $showsDetails) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(midi.connectionHealth.label).font(.headline)
                    Spacer()
                    Button("Done") { showsDetails = false }
                }
                Text(midi.connectionHealth.explanation)
                    .font(.callout)
                if let age = midi.feedbackAgeSeconds {
                    Text("Last MIDI feedback: \(age)s ago").monospacedDigit()
                } else {
                    Text("No feedback received from this Logic session")
                }
                if let acknowledgement = midi.lastConfirmedTransport {
                    Text(acknowledgement)
                }
                if let error = midi.lastSendError {
                    Text(error).foregroundStyle(LogicTheme.red)
                }
                Divider()
                Text("Logic → Control Surfaces → Setup\nMackie Control\nInput: CueX → Logic\nOutput: Logic → CueX")
                Text("For song locating and Stop, enable Listen to MIDI Machine Control (MMC) input in Logic’s project synchronization settings.")
                Text(midi.status).foregroundStyle(LogicTheme.secondaryText)
            }
            .font(.caption)
            .padding(16)
            .frame(width: 320)
            .background(LogicTheme.panel)
        }
    }

    private var color: Color {
        switch midi.connectionHealth {
        case .connected: LogicTheme.green
        case .waiting, .idle: LogicTheme.amber
        case .logicClosed: LogicTheme.secondaryText
        case .midiUnavailable, .feedbackLost, .commandUnconfirmed, .sendFailed: LogicTheme.red
        }
    }
}
