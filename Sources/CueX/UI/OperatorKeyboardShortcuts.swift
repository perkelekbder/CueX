import AppKit
import SwiftUI

/// Intercept keys before List's own selection handling, only in the operator
/// window. Text editors, sheets, and other apps keep their normal key handling.
struct OperatorKeyboardShortcuts: NSViewRepresentable {
    enum Action {
        case resetPlayback, stopPlayback, startPlayback, togglePlayback, toggleCycle, previousSong, nextSong

        init?(keyCode: UInt16) {
            switch keyCode {
            case 36, 76: self = .resetPlayback // Return and numeric-keypad Enter
            case 29, 82: self = .stopPlayback // Main keyboard and numeric-keypad 0
            case 49: self = .togglePlayback
            case 8: self = .toggleCycle
            case 43, 126: self = .previousSong
            case 47, 125: self = .nextSong
            default: return nil
            }
        }
    }

    var isEnabled: Bool
    var onAction: (Action) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.configuration = self
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configuration = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var configuration: OperatorKeyboardShortcuts?
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, let configuration = self.configuration, configuration.isEnabled,
                          let window = self.view?.window, window.isKeyWindow, NSApp.isActive,
                          event.window === window, window.attachedSheet == nil, NSApp.modalWindow == nil,
                          !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField) else { return false }
                    // Arrow events include function/numeric-pad flags. Preserve
                    // Command, Option, Shift, and Control combinations for macOS.
                    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                        .subtracting([.capsLock, .function, .numericPad])
                    guard modifiers.isEmpty,
                          let action = Action(keyCode: event.keyCode) else { return false }
                    // One action per press, even if a key is held down.
                    if !event.isARepeat { configuration.onAction(action) }
                    return true
                }
                return handled ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            configuration = nil
        }
    }
}
