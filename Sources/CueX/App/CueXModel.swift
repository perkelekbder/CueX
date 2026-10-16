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
            var importedProject = try LogicProjectImporter.importProject(at: url)
            let order = try notesStore.loadSectionOrder(for: url)
            let imported = importedProject.sections
            var seen = Set<String>()
            importedProject.sections = order.compactMap { id in
                guard seen.insert(id).inserted else { return nil }
                return imported.first { $0.id == id }
            } + imported.filter { !seen.contains($0.id) }
            let notes = try notesStore.load(for: url)
            let stops = try notesStore.loadStopAfterSongIDs(for: url)
            let isReload = project?.projectURL.standardizedFileURL == url.standardizedFileURL
            if !isReload {
                setlistURL = nil
                hasUnsavedSetlistChanges = false
            } else if setlistURL != nil, project?.sections != importedProject.sections {
                hasUnsavedSetlistChanges = true
            }
            project = importedProject
            sectionNotes = notes
            stopAfterSongIDs = stops
            playlistAutomation.configure(project: importedProject, savedIDs: stops)
        } catch {
            errorMessage = error.localizedDescription
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
            for candidate in [nearby, original] where FileManager.default.fileExists(atPath: candidate.path) {
                let scope = candidate.startAccessingSecurityScopedResource()
                defer { if scope { candidate.stopAccessingSecurityScopedResource() } }
                if let imported = try? LogicProjectImporter.importProject(at: candidate),
                   let matching = try? document.applying(to: imported) {
                    restoredProject = matching
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
                restoredProject = try document.applying(to: LogicProjectImporter.importProject(at: selected))
            }
            guard let restored = restoredProject else { return }
            guard canReorder else {
                errorMessage = "Stop Logic playback before opening a setlist."
                return
            }
            let linkedURL = restored.projectURL
            let stops = Set(document.stopAfterSongIDs)
            try notesStore.saveConfiguration(notes: document.notes, stops: stops,
                order: document.sectionOrder, for: linkedURL)
            project = restored
            sectionNotes = document.notes
            stopAfterSongIDs = stops
            setlistURL = url
            rememberSetlist(url)
            hasUnsavedSetlistChanges = linkedURL.standardizedFileURL.path != document.logicProjectPath
            playlistAutomation.configure(project: restored, savedIDs: stops)
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
