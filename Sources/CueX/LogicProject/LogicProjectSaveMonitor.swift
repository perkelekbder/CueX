import Foundation

struct LogicProjectSaveSnapshot: Equatable, Sendable {
    struct FileStamp: Equatable, Sendable {
        let path: String
        let modified: Date?
        let size: UInt64
        let inode: UInt64
    }

    let files: [FileStamp]

    static func capture(at projectURL: URL) throws -> Self {
        let dataURL = try LogicProjectImporter.projectDataURL(in: projectURL)
        let metadataURL = dataURL.deletingLastPathComponent().appendingPathComponent("MetaData.plist")
        var urls = [dataURL]
        if FileManager.default.fileExists(atPath: metadataURL.path) { urls.append(metadataURL) }
        return try Self(files: urls.map { url in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return FileStamp(path: url.path, modified: attributes[.modificationDate] as? Date,
                size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0)
        })
    }
}

/// Stat the actual imported files, not display-state files or backup folders.
/// Polling survives Logic replacing files or the entire package during a save.
@MainActor
final class LogicProjectSaveMonitor {
    enum Event {
        case sample(LogicProjectSaveSnapshot, stable: Bool)
        case unavailable
    }

    private var task: Task<Void, Never>?
    private var scopedURL: URL?

    func watch(at url: URL, baseline: LogicProjectSaveSnapshot, onEvent: @escaping @MainActor (Event) -> Void) {
        stop()
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        task = Task {
            var previous = baseline
            var failedSamples = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                do {
                    let snapshot = try await Task.detached(priority: .utility) {
                        try LogicProjectSaveSnapshot.capture(at: url)
                    }.value
                    guard !Task.isCancelled else { return }
                    failedSamples = 0
                    onEvent(.sample(snapshot, stable: snapshot == previous))
                    previous = snapshot
                } catch {
                    guard !Task.isCancelled else { return }
                    failedSamples += 1
                    // Allow transient missing files during atomic saves.
                    if failedSamples == 6 { onEvent(.unavailable) }
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    deinit { task?.cancel() }
}
