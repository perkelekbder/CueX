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
                    appDelegate.prepareOperatorWindow()
                }
        }
        .defaultSize(width: 420, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Setlist…") { model.openSetlist() }
                    .keyboardShortcut("o")
                    .disabled(!model.canReorder)
                RecentSetlistsMenu(model: model)
                Button("Select Logic Project…") { model.chooseProject() }
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

        MenuBarExtra("CueX", systemImage: "music.note.list") {
            Button("Open CueX") { openWindow(id: "operator") }
            Divider()
            Button("Open Setlist…") {
                model.requestSetlistPicker()
                openWindow(id: "operator")
            }
            .disabled(!model.canReorder)
            RecentSetlistsMenu(model: model) { url in
                model.requestSetlistPicker(url: url)
                openWindow(id: "operator")
            }
            Button("Select Logic Project…") {
                model.requestProjectPicker()
                openWindow(id: "operator")
            }
            .disabled(!model.canReorder)
            if let project = model.project {
                Text(project.projectName)
                Text("\(project.sections.count) sections imported")
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Quit CueX") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }

    }
}

@MainActor
final class CueXAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: CueXModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The operator Window is the first scene, so SwiftUI creates it at
        // launch. Bring CueX forward as well when started from Terminal.
        NSApplication.shared.activate(ignoringOtherApps: true)
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
