import Foundation

enum LogicConnectionHealth: Equatable {
    case midiUnavailable, logicClosed, waiting, connected, idle, feedbackLost, commandUnconfirmed, sendFailed

    var label: String {
        switch self {
        case .midiUnavailable: "MIDI unavailable"
        case .logicClosed: "Logic not running"
        case .waiting: "Waiting for Logic"
        case .connected: "Logic connected"
        case .idle: "Logic idle · Unverified"
        case .feedbackLost: "Logic feedback lost"
        case .commandUnconfirmed: "Logic not responding"
        case .sendFailed: "MIDI send failed"
        }
    }

    var explanation: String {
        switch self {
        case .midiUnavailable: "CueX couldn’t create its MIDI ports. Restart CueX and check the MIDI status below."
        case .logicClosed: "Logic Pro is not running. Open Logic and a playback project."
        case .waiting: "Logic is running, but CueX hasn’t received control-surface feedback from this Logic session. Check the Mackie Control input and output ports."
        case .connected: "CueX is receiving recent control-surface feedback from Logic. This confirms incoming feedback, not whether MMC locating is enabled."
        case .idle: "Logic is running, but feedback has been quiet. Stopped transport may send no messages, so the MIDI route is currently unverified. Play or cue a song to check it."
        case .feedbackLost: "Logic last reported playback running, but clock feedback has stopped for more than 1.5 seconds. Check the control-surface routing and Logic’s state."
        case .commandUnconfirmed: "A Play or Stop command was sent, but Logic hasn’t confirmed the requested transport state within 2 seconds. Check both Mackie Control ports and MMC input."
        case .sendFailed: "Core MIDI reported an error while CueX was sending a command. See the error below."
        }
    }
}
