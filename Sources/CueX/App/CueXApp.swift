import SwiftUI

@main
struct CueXApp: App {
    @State private var model = CueXModel()
    @NSApplicationDelegateAdaptor(CueXAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    private var copySetlistAction: (() -> Void)? {
        guard model.project != nil else { return nil }
        return { model.copySetlist() }
    }

    var body: some Scene {
        Window("CueX", id: "operator") {
            OperatorView(model: model)
                .focusedSceneValue(\.copySetlist, copySetlistAction)
                .onAppear {
                    appDelegate.model = model
                    appDelegate.showOperatorWindow = { [openWindow] in openWindow(id: "operator") }
                    appDelegate.prepareOperatorWindow()
                }
        }
        .defaultSize(width: 420, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            SetlistClipboardCommands()
            CommandGroup(replacing: .newItem) {
                Button("Open Setlist…") {
                    openWindow(id: "operator")
                    model.openSetlist()
                }
                .keyboardShortcut("o")
                .disabled(!model.canReorder)
                RecentSetlistsMenu(model: model) { url in
                    openWindow(id: "operator")
                    model.openSetlist(at: url)
                }
                Button("Select Logic Project…") {
                    openWindow(id: "operator")
                    model.chooseProject()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!model.canReorder)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Setlist…") { model.saveSetlist() }
                    .keyboardShortcut("s")
                    .disabled(model.project?.sections.isEmpty != false)
                Button("Save Setlist As…") { model.saveSetlist(asNewFile: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.project?.sections.isEmpty != false)
            }
        }
    }
}

@MainActor
final class CueXAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: CueXModel?
    var showOperatorWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The operator Window is the first scene, so SwiftUI creates it at
        // launch. Bring CueX forward as well when started from Terminal.
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showOperatorWindow?()
        sender.activate(ignoringOtherApps: true)
        return false
    }

    func prepareOperatorWindow() {
        // Migrate the old landscape window once; later launches preserve resizing.
        DispatchQueue.main.async {
            let defaults = UserDefaults.standard
            guard !defaults.bool(forKey: "CueX.verticalWindowLayout"),
                  let window = NSApplication.shared.windows.first(where: { $0.title == "CueX" && $0.canBecomeMain }) else { return }
            let availableHeight = (window.screen?.visibleFrame.height ?? 840) - 80
            window.setContentSize(NSSize(width: 420, height: max(560, min(760, availableHeight))))
            window.center()
            defaults.set(true, forKey: "CueX.verticalWindowLayout")
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.confirmSetlistReplacement() == false ? .terminateCancel : .terminateNow
    }
}

private struct CopySetlistActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    fileprivate var copySetlist: (() -> Void)? {
        get { self[CopySetlistActionKey.self] }
        set { self[CopySetlistActionKey.self] = newValue }
    }
}

private struct SetlistClipboardCommands: Commands {
    @FocusedValue(\.copySetlist) private var copySetlist

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Copy Setlist") { copySetlist?() }
                .keyboardShortcut("c")
                .disabled(copySetlist == nil)
        }
    }
}
