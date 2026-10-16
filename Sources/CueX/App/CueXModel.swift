import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class CueXModel {
    private(set) var project: ImportedLogicProject?
    private(set) var sectionNotes: [String: String] = [:]
    private(set) var stopAfterSongIDs: Set<String> = []
    private(set) var setlistURL: URL?
    private(set) var hasUnsavedSetlistChanges = false
    private(set) var recentSetlistURLs: [URL] = RecentSetlistsStore().load()
    private let recentSetlistsStore = RecentSetlistsStore()
    var errorMessage: String?
    var isImporting = false
    private(set) var projectChangeNotice: String?
    private(set) var reloadedSectionIDs: [String: String] = [:]
    @ObservationIgnored private let saveMonitor = LogicProjectSaveMonitor()
    @ObservationIgnored private var importedSnapshot: LogicProjectSaveSnapshot?
    private var pendingSnapshot: LogicProjectSaveSnapshot?
    @ObservationIgnored private var reloadFailures = 0
    private var projectUnavailable = false
    private let notesStore = OperatorNotesStore()
    let midiController = LogicMIDIController()
    let playlistAutomation: PlaylistAutomation

    init() {
        playlistAutomation = PlaylistAutomation(midi: midiController)
    }

    func stopsAfter(_ section: ArrangementSection) -> Bool {
        guard let project else { return false }
        return PlaylistStopPolicy.isEnabled(for: section, in: project, savedIDs: stopAfterSongIDs)
    }

    func setStopsAfter(_ enabled: Bool, for section: ArrangementSection) {
        guard let project, section.id != project.sections.last?.id else { return }
        var updated = stopAfterSongIDs
        if enabled { updated.insert(section.id) } else { updated.remove(section.id) }
        do {
            try notesStore.saveStopAfterSongIDs(updated, for: project.projectURL)
            stopAfterSongIDs = updated
            hasUnsavedSetlistChanges = true
            playlistAutomation.updateOptions(updated)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    var activeSection: ArrangementSection? {
        guard let position = midiController.position else { return nil }
        return project?.section(at: position)
    }

    var songProgress: SongProgress? {
        guard let project, let position = midiController.position else { return nil }
        return SongProgress(project: project, position: position)
    }

    func chooseProject() {
        guard canReorder, confirmSetlistReplacement() else { return }
        let panel = NSOpenPanel()
        panel.title = "Select a Logic Pro project"
        panel.prompt = "Import Sections"
        panel.message = "CueX reads the saved Arrangement section list. It won’t change your Logic project."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.package]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importProject(at: url)
    }

    func importProject(at url: URL) {
        guard canReorder else { return }
        isImporting = true
        errorMessage = nil
        let hasScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasScope { url.stopAccessingSecurityScopedResource() }
            isImporting = false
        }
        do {
            let snapshot = try LogicProjectSaveSnapshot.capture(at: url)
            let imported = try LogicProjectImporter.importProject(at: url)
            try applyImportedProject(imported)
            monitorProject(at: url, baseline: snapshot)
            projectChangeNotice = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func applyImportedProject(_ imported: ImportedLogicProject) throws {
        let url = imported.projectURL
        let isReload = project?.projectURL.standardizedFileURL == url.standardizedFileURL
        var restored = imported
        var notes: [String: String]
        var stops: Set<String>
        var replacements: [String: String] = [:]
        if isReload, let previous = project {
            let merge = ProjectReloadMerger.merge(previous: previous, imported: imported)
            restored = merge.project
            replacements = merge.sectionIDs
            // Keep orphaned settings locally, in case removed songs are restored.
            notes = sectionNotes
            stops = stopAfterSongIDs
            for (oldID, newID) in replacements where oldID != newID {
                if let note = notes.removeValue(forKey: oldID) { notes[newID] = note }
                if stops.remove(oldID) != nil { stops.insert(newID) }
            }
            try notesStore.saveConfiguration(notes: notes, stops: stops, order: restored.sections.map(\.id), for: url)
        } else {
            let order = try notesStore.loadSectionOrder(for: url)
            var seen = Set<String>()
            restored.sections = order.compactMap { id in
                guard seen.insert(id).inserted else { return nil }
                return imported.sections.first { $0.id == id }
            } + imported.sections.filter { !seen.contains($0.id) }
            notes = try notesStore.load(for: url)
            stops = try notesStore.loadStopAfterSongIDs(for: url)
        }
        if !isReload {
            setlistURL = nil
            hasUnsavedSetlistChanges = false
        } else if setlistURL != nil, project?.sections != restored.sections {
            hasUnsavedSetlistChanges = true
        }
        reloadedSectionIDs = replacements
        project = restored
        sectionNotes = notes
        stopAfterSongIDs = stops
        playlistAutomation.configure(project: restored, savedIDs: stops)
    }

    private func monitorProject(at url: URL, baseline: LogicProjectSaveSnapshot) {
        importedSnapshot = baseline
        pendingSnapshot = nil
        reloadFailures = 0
        projectUnavailable = false
        saveMonitor.watch(at: url, baseline: baseline) { [weak self] event in
            guard let self, self.project?.projectURL.standardizedFileURL == url.standardizedFileURL else { return }
            self.handleProjectSave(event, at: url)
        }
    }

    private func handleProjectSave(_ event: LogicProjectSaveMonitor.Event, at url: URL) {
        switch event {
        case .unavailable:
            projectUnavailable = true
            projectChangeNotice = "Logic project unavailable · Keeping previous state"
        case let .sample(snapshot, stable):
            if projectUnavailable {
                projectUnavailable = false
                if pendingSnapshot != nil {
                    projectChangeNotice = reloadFailures >= 3
                        ? "Couldn’t reload project · Click to retry"
                        : "Logic project changed · Reload pending"
                } else {
                    projectChangeNotice = nil
                }
            }
            guard snapshot != importedSnapshot else {
                if pendingSnapshot != nil {
                    pendingSnapshot = nil
                    reloadFailures = 0
                    projectChangeNotice = "Logic project is up to date"
                }
                return
            }
            if snapshot != pendingSnapshot {
                pendingSnapshot = snapshot
                reloadFailures = 0
                projectChangeNotice = canReorder ? "Logic project changed · Reloading…" : "Logic project changed · Reload after Stop"
                // Show the notice before replacing any state, even for a save
                // whose final files already matched the previous poll.
                return
            }
            guard stable, canReorder, !isImporting, errorMessage == nil, reloadFailures < 3,
                  NSApplication.shared.modalWindow == nil,
                  !NSApplication.shared.windows.contains(where: { $0.attachedSheet != nil }) else { return }
            isImporting = true
            defer { isImporting = false }
            do {
                let imported = try LogicProjectImporter.importProject(at: url)
                // Do not commit a mixture of files from two saves.
                guard try LogicProjectSaveSnapshot.capture(at: url) == snapshot else { return }
                try applyImportedProject(imported)
                importedSnapshot = snapshot
                pendingSnapshot = nil
                reloadFailures = 0
                projectChangeNotice = "Logic project saved · Reloaded"
            } catch {
                reloadFailures += 1
                if reloadFailures == 3 {
                    projectChangeNotice = "Couldn’t reload project · Click to retry"
                }
            }
        }
    }

    var hasPendingProjectReload: Bool { pendingSnapshot != nil || projectUnavailable }

    var canStartPlayback: Bool {
        midiController.isReady && !playlistAutomation.isTransitioning && !hasPendingProjectReload
    }

    func handleProjectChangeNotice() {
        if hasPendingProjectReload {
            guard canReorder, let project else { return }
            importProject(at: project.projectURL)
        } else {
            projectChangeNotice = nil
        }
    }

    var canReorder: Bool { midiController.isPlaying != true && !playlistAutomation.isTransitioning }

    func moveSections(from source: IndexSet, to destination: Int) {
        guard canReorder, var updated = project, !source.isEmpty,
              source.allSatisfy({ updated.sections.indices.contains($0) }),
              (0...updated.sections.count).contains(destination) else { return }
        let moving = source.sorted().map { updated.sections[$0] }
        for index in source.sorted(by: >) { updated.sections.remove(at: index) }
        let insertionIndex = destination - source.filter { $0 < destination }.count
        updated.sections.insert(contentsOf: moving, at: insertionIndex)
        guard updated.sections != project?.sections else { return }
        do {
            try notesStore.saveSectionOrder(updated.sections.map(\.id), for: updated.projectURL)
            project = updated
            hasUnsavedSetlistChanges = true
            playlistAutomation.configure(project: updated, savedIDs: stopAfterSongIDs)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func note(for section: ArrangementSection) -> String {
        sectionNotes[section.id] ?? ""
    }

    func updateNote(_ note: String, for section: ArrangementSection) {
        guard sectionNotes[section.id, default: ""] != note else { return }
        sectionNotes[section.id] = note
        hasUnsavedSetlistChanges = true
        guard let projectURL = project?.projectURL else { return }
        do {
            try notesStore.save(sectionNotes, for: projectURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var setlistTitle: String {
        var title = setlistURL?.deletingPathExtension().lastPathComponent ?? "Unsaved setlist"
        if title.hasSuffix(".cuex") { title.removeLast(5) }
        return title + (hasUnsavedSetlistChanges ? " •" : "")
    }

    @discardableResult
    func saveSetlist(asNewFile: Bool = false) -> Bool {
        guard let project, !project.sections.isEmpty else { return false }
        var destination = setlistURL
        if asNewFile || destination == nil {
            let panel = NSSavePanel()
            panel.title = "Save CueX Setlist"
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = setlistURL?.lastPathComponent ?? "\(project.projectName).cuex.json"
            panel.message = "Saves song order, notes, and stop settings. Keep the Logic project separately."
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            destination = url
        }
        guard let destination else { return false }
        let hasScope = destination.startAccessingSecurityScopedResource()
        defer { if hasScope { destination.stopAccessingSecurityScopedResource() } }
        do {
            let validIDs = Set(project.sections.map(\.id))
            let document = SetlistDocument(project: project,
                notes: sectionNotes.filter { validIDs.contains($0.key) },
                stops: stopAfterSongIDs.intersection(validIDs))
            try document.write(to: destination)
            setlistURL = destination
            rememberSetlist(destination)
            hasUnsavedSetlistChanges = false
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func openSetlist() {
        guard canReorder, confirmSetlistReplacement() else { return }
        let panel = NSOpenPanel()
        panel.title = "Open CueX Setlist"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadSetlist(at: url)
    }

    func openSetlist(at url: URL) {
        guard canReorder, confirmSetlistReplacement() else { return }
        loadSetlist(at: url)
    }

    private func loadSetlist(at url: URL) {
        let hasScope = url.startAccessingSecurityScopedResource()
        defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "This setlist is no longer available at \(url.path). Use Open Setlist to locate it, or Clear Menu to clear recent setlists."
            return
        }
        do {
            let document = try SetlistDocument.read(from: url)
            // Prefer the project beside a transferred setlist, then its original path.
            let nearby = url.deletingLastPathComponent().appendingPathComponent(document.logicProjectName)
            let original = URL(fileURLWithPath: document.logicProjectPath)
            var restoredProject: ImportedLogicProject?
            var restoredSnapshot: LogicProjectSaveSnapshot?
            for candidate in [nearby, original] where FileManager.default.fileExists(atPath: candidate.path) {
                let scope = candidate.startAccessingSecurityScopedResource()
                defer { if scope { candidate.stopAccessingSecurityScopedResource() } }
                if let snapshot = try? LogicProjectSaveSnapshot.capture(at: candidate),
                   let imported = try? LogicProjectImporter.importProject(at: candidate),
                   let matching = try? document.applying(to: imported) {
                    restoredProject = matching
                    restoredSnapshot = snapshot
                    break
                }
            }
            if restoredProject == nil {
                let relink = NSOpenPanel()
                relink.title = "Locate Logic Project"
                relink.message = "CueX couldn’t find a matching project. Choose \(document.logicProjectName) for this setlist."
                relink.allowedContentTypes = [.package]
                relink.canChooseDirectories = true
                relink.allowsMultipleSelection = false
                guard relink.runModal() == .OK, let selected = relink.url else { return }
                let scope = selected.startAccessingSecurityScopedResource()
                defer { if scope { selected.stopAccessingSecurityScopedResource() } }
                restoredSnapshot = try LogicProjectSaveSnapshot.capture(at: selected)
                restoredProject = try document.applying(to: LogicProjectImporter.importProject(at: selected))
            }
            guard let restored = restoredProject, let restoredSnapshot else { return }
            guard canReorder else {
                errorMessage = "Stop Logic playback before opening a setlist."
                return
            }
            let linkedURL = restored.projectURL
            let stops = Set(document.stopAfterSongIDs)
            try notesStore.saveConfiguration(notes: document.notes, stops: stops,
                order: document.sectionOrder, for: linkedURL)
            reloadedSectionIDs = [:]
            project = restored
            sectionNotes = document.notes
            stopAfterSongIDs = stops
            setlistURL = url
            rememberSetlist(url)
            hasUnsavedSetlistChanges = linkedURL.standardizedFileURL.path != document.logicProjectPath
            playlistAutomation.configure(project: restored, savedIDs: stops)
            monitorProject(at: linkedURL, baseline: restoredSnapshot)
            projectChangeNotice = nil
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func rememberSetlist(_ url: URL) {
        let normalized = url.standardizedFileURL
        recentSetlistURLs = Array(([normalized] + recentSetlistURLs.filter { $0 != normalized }).prefix(10))
        recentSetlistsStore.save(recentSetlistURLs)
    }

    func clearRecentSetlists() {
        recentSetlistURLs = []
        recentSetlistsStore.save([])
    }

    /// The local working copy is automatic; portable setlist files use explicit Save.
    func confirmSetlistReplacement() -> Bool {
        guard hasUnsavedSetlistChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to your setlist?"
        alert.informativeText = "Save a setlist file to recall this version later."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveSetlist()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    func locate(_ section: ArrangementSection) {
        playlistAutomation.manualLocate(section)
    }
}
