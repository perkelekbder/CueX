import SwiftUI

@main
struct CueXApp: App {
    @State private var model = CueXModel()
    @NSApplicationDelegateAdaptor(CueXAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("CueX", id: "operator") {
            OperatorView(model: model)
                .onAppear {
                    appDelegate.model = model
                    appDelegate.showOperatorWindow = { [openWindow] in openWindow(id: "operator") }
                    appDelegate.prepareOperatorWindow()
                }
        }
        .defaultSize(width: 420, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
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
final class CueXAppDelegate: NSObject, NSApplicationDelegate, NSUserInterfaceValidations {
    weak var model: CueXModel?
    private weak var operatorWindow: NSWindow?
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
            guard let window = NSApplication.shared.windows.first(where: { $0.title == "CueX" && $0.canBecomeMain }) else { return }
            self.operatorWindow = window
            let defaults = UserDefaults.standard
            guard !defaults.bool(forKey: "CueX.verticalWindowLayout") else { return }
            let availableHeight = (window.screen?.visibleFrame.height ?? 840) - 80
            window.setContentSize(NSSize(width: 420, height: max(560, min(760, availableHeight))))
            window.center()
            defaults.set(true, forKey: "CueX.verticalWindowLayout")
        }
    }

    // The standard Edit → Copy action reaches the app delegate only when
    // an earlier responder (such as a text editor) doesn't handle Copy.
    @objc func copy(_ sender: Any?) {
        guard canCopySetlist else { return }
        model?.copySetlist()
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) { return canCopySetlist }
        return true
    }

    private var canCopySetlist: Bool {
        guard let operatorWindow else { return false }
        return NSApp.isActive && NSApp.keyWindow === operatorWindow
            && operatorWindow.attachedSheet == nil && NSApp.modalWindow == nil
            && model?.project != nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.confirmSetlistReplacement() == false ? .terminateCancel : .terminateNow
    }
}
