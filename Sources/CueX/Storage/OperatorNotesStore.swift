import CryptoKit
import Foundation

struct OperatorNotesStore {
    private let baseDirectory: URL?

    init(baseDirectory: URL? = nil) { self.baseDirectory = baseDirectory }

    private struct Document: Codable {
        var formatVersion: Int
        var projectPath: String
        var notes: [String: String]
        var stopAfterSongIDs: [String]?
        var sectionOrder: [String]?
    }

    func load(for projectURL: URL) throws -> [String: String] {
        let fileURL = try notesFileURL(for: projectURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
        guard document.formatVersion == 1,
              document.projectPath == projectURL.standardizedFileURL.path else {
            throw StoreError.unsupportedNotesFile
        }
        return document.notes
    }

    func save(_ notes: [String: String], for projectURL: URL) throws {
        let fileURL = try notesFileURL(for: projectURL)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let document = Document(
            formatVersion: 1,
            projectPath: projectURL.standardizedFileURL.path,
            notes: notes,
            stopAfterSongIDs: try loadStopAfterSongIDs(for: projectURL).sorted(),
            sectionOrder: try loadSectionOrder(for: projectURL)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    func loadStopAfterSongIDs(for projectURL: URL) throws -> Set<String> {
        let fileURL = try notesFileURL(for: projectURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
        guard document.formatVersion == 1, document.projectPath == projectURL.standardizedFileURL.path else {
            throw StoreError.unsupportedNotesFile
        }
        return Set(document.stopAfterSongIDs ?? [])
    }

    func saveStopAfterSongIDs(_ ids: Set<String>, for projectURL: URL) throws {
        let fileURL = try notesFileURL(for: projectURL)
        let notes = try load(for: projectURL)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let document = Document(formatVersion: 1, projectPath: projectURL.standardizedFileURL.path,
                                notes: notes, stopAfterSongIDs: ids.sorted(), sectionOrder: try loadSectionOrder(for: projectURL))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    func loadSectionOrder(for projectURL: URL) throws -> [String] {
        let fileURL = try notesFileURL(for: projectURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
        guard document.formatVersion == 1, document.projectPath == projectURL.standardizedFileURL.path else {
            throw StoreError.unsupportedNotesFile
        }
        return document.sectionOrder ?? []
    }

    func saveSectionOrder(_ ids: [String], for projectURL: URL) throws {
        let notes = try load(for: projectURL)
        let stops = try loadStopAfterSongIDs(for: projectURL)
        let fileURL = try notesFileURL(for: projectURL)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let document = Document(formatVersion: 1, projectPath: projectURL.standardizedFileURL.path,
                                notes: notes, stopAfterSongIDs: stops.sorted(), sectionOrder: ids)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    func saveConfiguration(notes: [String: String], stops: Set<String>, order: [String], for projectURL: URL) throws {
        let fileURL = try notesFileURL(for: projectURL)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let document = Document(formatVersion: 1, projectPath: projectURL.standardizedFileURL.path,
                                notes: notes, stopAfterSongIDs: stops.sorted(), sectionOrder: order)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    private func notesFileURL(for projectURL: URL) throws -> URL {
        guard let supportDirectory = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StoreError.applicationSupportUnavailable
        }
        let path = projectURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return supportDirectory
            .appendingPathComponent("CueX/Projects", isDirectory: true)
            .appendingPathComponent("\(digest).json", isDirectory: false)
    }

    private enum StoreError: LocalizedError {
        case applicationSupportUnavailable
        case unsupportedNotesFile

        var errorDescription: String? {
            switch self {
            case .applicationSupportUnavailable:
                return "CueX couldn’t find the Application Support folder for your notes."
            case .unsupportedNotesFile:
                return "The saved CueX notes file doesn’t match this Logic project or uses an unsupported format."
            }
        }
    }
}
