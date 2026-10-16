import Foundation

struct RecentSetlistsStore {
    private let defaults = UserDefaults.standard
    private let key = "CueX.recentSetlistPaths"

    func load() -> [URL] {
        var seen = Set<URL>()
        return Array((defaults.stringArray(forKey: key) ?? []).compactMap { path in
            guard path.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            return seen.insert(url).inserted ? url : nil
        }.prefix(10))
    }

    func save(_ urls: [URL]) {
        defaults.set(urls.map(\.path), forKey: key)
    }
}
