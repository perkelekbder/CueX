import SwiftUI

struct RecentSetlistsMenu: View {
    let model: CueXModel
    var onOpen: ((URL) -> Void)?

    var body: some View {
        Menu("Open Recent") {
            if model.recentSetlistURLs.isEmpty {
                Text("No Recent Setlists")
            }
            ForEach(model.recentSetlistURLs, id: \.self) { url in
                Button(title(for: url)) {
                    if let onOpen { onOpen(url) } else { model.openSetlist(at: url) }
                }
                .help(url.path)
                .disabled(!model.canReorder)
            }
            Divider()
            Button("Clear Menu") { model.clearRecentSetlists() }
                .disabled(model.recentSetlistURLs.isEmpty)
        }
    }

    private func title(for url: URL) -> String {
        let hasDuplicateName = model.recentSetlistURLs.filter { $0.lastPathComponent == url.lastPathComponent }.count > 1
        return hasDuplicateName
            ? "\(url.lastPathComponent) — \(url.deletingLastPathComponent().path)"
            : url.lastPathComponent
    }
}
