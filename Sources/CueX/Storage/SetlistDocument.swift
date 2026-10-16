import Foundation

/// A portable snapshot of CueX settings. Audio and Logic project data stay in .logicx.
struct SetlistDocument: Codable {
    let formatVersion: Int
    let logicProjectPath: String
    let logicProjectName: String
    let sectionOrder: [String]
    let notes: [String: String]
    let stopAfterSongIDs: [String]

    init(project: ImportedLogicProject, notes: [String: String], stops: Set<String>) {
        formatVersion = 1
        logicProjectPath = project.projectURL.standardizedFileURL.path
        logicProjectName = project.projectURL.lastPathComponent
        sectionOrder = project.sections.map(\.id)
        self.notes = notes
        stopAfterSongIDs = stops.sorted()
    }

    static func read(from url: URL) throws -> Self {
        let document = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard document.formatVersion == 1 else { throw FileError.unsupportedVersion }
        guard !document.sectionOrder.isEmpty,
              Set(document.sectionOrder).count == document.sectionOrder.count,
              Set(document.stopAfterSongIDs).isSubset(of: Set(document.sectionOrder)),
              Set(document.notes.keys).isSubset(of: Set(document.sectionOrder)),
              document.logicProjectName == URL(fileURLWithPath: document.logicProjectName).lastPathComponent,
              document.logicProjectName.lowercased().hasSuffix(".logicx") else { throw FileError.invalidContents }
        return document
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    func applying(to project: ImportedLogicProject) throws -> ImportedLogicProject {
        // Never silently apply song settings to a different or changed arrangement.
        guard project.sections.count == sectionOrder.count,
              Set(sectionOrder) == Set(project.sections.map(\.id)) else { throw FileError.arrangementMismatch }
        let sections = Dictionary(uniqueKeysWithValues: project.sections.map { ($0.id, $0) })
        var result = project
        result.sections = sectionOrder.compactMap { sections[$0] }
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
