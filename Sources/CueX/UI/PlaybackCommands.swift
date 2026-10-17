import SwiftUI

struct PlaybackActions {
    let canStop: Bool
    let canStart: Bool
    let canToggleCycle: Bool
    let canPrevious: Bool
    let canNext: Bool
    let spaceStops: Bool
    let send: (OperatorKeyboardShortcuts.Action) -> Void

    func isEnabled(_ action: OperatorKeyboardShortcuts.Action) -> Bool {
        switch action {
        case .resetPlayback, .stopPlayback: canStop
        case .startPlayback: canStart
        case .togglePlayback: spaceStops ? canStop : canStart
        case .toggleCycle: canToggleCycle
        case .previousSong: canPrevious
        case .nextSong: canNext
        }
    }

    func perform(_ action: OperatorKeyboardShortcuts.Action) {
        guard isEnabled(action) else { return }
        send(action)
    }
}

private struct PlaybackActionsKey: FocusedValueKey {
    typealias Value = PlaybackActions
}

extension FocusedValues {
    var playbackActions: PlaybackActions? {
        get { self[PlaybackActionsKey.self] }
        set { self[PlaybackActionsKey.self] = newValue }
    }
}

struct PlaybackCommands: Commands {
    @FocusedValue(\.playbackActions) private var actions

    private var stopShortcut: KeyboardShortcut {
        actions?.spaceStops == true
            ? KeyboardShortcut(.space, modifiers: []) : KeyboardShortcut("0", modifiers: [])
    }

    private var startShortcut: KeyboardShortcut? {
        actions?.spaceStops == true ? nil : KeyboardShortcut(.space, modifiers: [])
    }

    var body: some Commands {
        CommandMenu("Playback") {
            Button { actions?.perform(.resetPlayback) } label: {
                Label("Reset Playback", systemImage: "arrow.counterclockwise")
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(actions?.canStop != true)
            Button { actions?.perform(.stopPlayback) } label: {
                Label("Stop Playback", systemImage: "stop.fill")
            }
            .keyboardShortcut(stopShortcut)
            .disabled(actions?.canStop != true)
            .help("0 stops playback; Space also stops while playing or during a scheduled pause.")
            Button { actions?.perform(.startPlayback) } label: {
                Label("Start Playback", systemImage: "play.fill")
            }
            .keyboardShortcut(startShortcut)
            .disabled(actions?.canStart != true)
            Button { actions?.perform(.toggleCycle) } label: {
                Label("Toggle Cycle", systemImage: "repeat")
            }
            .keyboardShortcut("c", modifiers: [])
            .disabled(actions?.canToggleCycle != true)
            Divider()
            Button { actions?.perform(.previousSong) } label: {
                Label("Previous", systemImage: "backward.end.fill")
            }
            .keyboardShortcut(",", modifiers: [])
            .disabled(actions?.canPrevious != true)
            .help("Previous song (, or ↑)")
            Button { actions?.perform(.nextSong) } label: {
                Label("Next", systemImage: "forward.end.fill")
            }
            .keyboardShortcut(".", modifiers: [])
            .disabled(actions?.canNext != true)
            .help("Next song (. or ↓)")
        }
    }
}
