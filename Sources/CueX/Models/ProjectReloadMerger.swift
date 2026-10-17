import Foundation

struct ProjectReloadMerge {
    let project: ImportedLogicProject
    let sectionIDs: [String: String]
}

enum ProjectReloadMerger {
    static func merge(previous: ImportedLogicProject, imported: ImportedLogicProject) -> ProjectReloadMerge {
        var matches: [String: String] = [:]
        var usedNewIDs = Set<String>()
        let newIDs = Set(imported.sections.map(\.id))
        for old in previous.sections where newIDs.contains(old.id) {
            matches[old.id] = old.id
            usedNewIDs.insert(old.id)
        }
        // Preserve moved songs by unique name, then renamed songs by position.
        // Ambiguous changes remain unmatched instead of borrowing another note.
        for matchByName in [true, false] {
            let oldGroups = Dictionary(grouping: previous.songs.filter { matches[$0.id] == nil }) {
                matchByName ? $0.name.trimmingCharacters(in: .whitespacesAndNewlines) : String($0.startTick)
            }
            let newGroups = Dictionary(grouping: imported.sections.filter { !usedNewIDs.contains($0.id) }) {
                matchByName ? $0.name.trimmingCharacters(in: .whitespacesAndNewlines) : String($0.startTick)
            }
            for (key, old) in oldGroups {
                guard old.count == 1, let new = newGroups[key], new.count == 1 else { continue }
                matches[old[0].id] = new[0].id
                usedNewIDs.insert(new[0].id)
            }
        }
        var result = imported
        result.sections = previous.sections.compactMap { old in
            if !old.isSong { return old }
            guard let newID = matches[old.id] else { return nil }
            return imported.sections.first { $0.id == newID }
        } + imported.sections.filter { !usedNewIDs.contains($0.id) }
        return ProjectReloadMerge(project: result, sectionIDs: matches)
    }
}
