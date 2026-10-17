import Foundation

/// A portable snapshot of CueX settings. Audio and Logic project data stay in .logicx.
struct SetlistDocument: Codable {
    let formatVersion: Int
    let logicProjectPath: String
    let logicProjectName: String
    let sectionOrder: [String]
    let notes: [String: String]
    let stopAfterSongIDs: [String]
    var customBlocks: [ArrangementSection]?

    init(project: ImportedLogicProject, notes: [String: String], stops: Set<String>) {
        formatVersion = 2
        logicProjectPath = project.projectURL.standardizedFileURL.path
        logicProjectName = project.projectURL.lastPathComponent
        sectionOrder = project.sections.map(\.id)
        customBlocks = project.sections.filter { !$0.isSong }
        self.notes = notes
        stopAfterSongIDs = stops.sorted()
    }

    static func read(from url: URL) throws -> Self {
        let document = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard (1...2).contains(document.formatVersion) else { throw FileError.unsupportedVersion }
        guard !document.sectionOrder.isEmpty,
              Set(document.sectionOrder).count == document.sectionOrder.count,
              Set(document.stopAfterSongIDs).isSubset(of: Set(document.sectionOrder)),
              Set(document.notes.keys).isSubset(of: Set(document.sectionOrder)),
              document.logicProjectName == URL(fileURLWithPath: document.logicProjectName).lastPathComponent,
              document.logicProjectName.lowercased().hasSuffix(".logicx") else { throw FileError.invalidContents }
        let blocks = document.customBlocks ?? []
        guard Set(blocks.map(\.id)).count == blocks.count,
              blocks.allSatisfy({ entry in
                  entry.id.hasPrefix("block|") && entry.block?.isValid == true
                      && entry.startTick == 0 && entry.lengthTicks == 0
                      && document.sectionOrder.contains(entry.id)
              }) else { throw FileError.invalidContents }
        return document
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    func applying(to project: ImportedLogicProject) throws -> ImportedLogicProject {
        // Never silently apply song settings to a different or changed arrangement.
        let blocks = customBlocks ?? []
        let blockIDs = Set(blocks.map(\.id))
        let songOrder = sectionOrder.filter { !blockIDs.contains($0) }
        guard project.sections.count == songOrder.count,
              Set(songOrder) == Set(project.sections.map(\.id)),
              blockIDs.isDisjoint(with: Set(project.sections.map(\.id))) else { throw FileError.arrangementMismatch }
        let sections = Dictionary(uniqueKeysWithValues: (project.sections + blocks).map { ($0.id, $0) })
        var result = project
        result.sections = sectionOrder.compactMap { sections[$0] }
        result.ensureFullStop()
        return result
    }

    enum FileError: LocalizedError {
        case unsupportedVersion, invalidContents, arrangementMismatch

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: "This setlist was saved in a format this version of CueX doesn’t support."
            case .invalidContents: "This file doesn’t contain a valid CueX setlist."
            case .arrangementMismatch: "The Logic project’s Arrangement sections don’t match this setlist. Choose the original project. If you’ve renamed, moved, added, or removed sections in Logic, import the updated project and save a new setlist."
            }
        }
    }
}
