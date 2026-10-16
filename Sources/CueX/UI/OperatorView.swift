import SwiftUI

struct OperatorView: View {
    @Bindable var model: CueXModel
    @State private var selectedSectionID: String?
    @State private var suppressNextLocate = false
    @State private var editingSectionID: String?

    var body: some View {
        // Let the list absorb size changes while controls and footer stay pinned.
        GeometryReader { _ in
            VStack(spacing: 0) {
                fileControls
                Divider()
                setlist
                Divider()
                transport
                Divider()
                statusFooter
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 360, minHeight: 560)
        .background {
            OperatorKeyboardShortcuts(
                isEnabled: model.project != nil && model.midiController.isReady
                    && editingSectionID == nil && model.errorMessage == nil && !model.isImporting,
                onAction: handleKeyboardAction
            )
        }
        .alert("CueX couldn’t complete the action", isPresented: errorPresented) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Unknown import error.")
        }
        .onAppear(perform: ensureSelectedSection)
        .onChange(of: model.project?.sections.map(\.id)) { _, _ in
            editingSectionID = nil
            ensureSelectedSection()
        }
        .onChange(of: selectedSectionID) { _, sectionID in
            if suppressNextLocate {
                suppressNextLocate = false
                return
            }
            guard let section = model.project?.sections.first(where: { $0.id == sectionID }) else { return }
            model.locate(section)
        }
        .onChange(of: model.playlistAutomation.armedSectionID) { _, sectionID in
            guard let sectionID, sectionID != selectedSectionID else { return }
            // The automation already located this song after Stop was confirmed.
            suppressNextLocate = true
            selectedSectionID = sectionID
        }
    }

    private var fileControls: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Open Setlist…") { model.openSetlist() }
                    .disabled(!model.canReorder)
                RecentSetlistsMenu(model: model)
                Button("Save Setlist…") { model.saveSetlist() }
                    .disabled(model.project?.sections.isEmpty != false)
                Button("Save Setlist As…") { model.saveSetlist(asNewFile: true) }
                    .disabled(model.project?.sections.isEmpty != false)
                Divider()
                Button("Select Logic Project…") { model.chooseProject() }
                    .disabled(!model.canReorder)
                Button("Reload Logic Project") {
                    if let project = model.project { model.importProject(at: project.projectURL) }
                }
                .disabled(model.project == nil || !model.canReorder)
            } label: {
                Text(model.project == nil ? "Open setlist" : model.setlistTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .help("Open, save, or reload a setlist")
            Button { model.saveSetlist() } label: {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(model.project?.sections.isEmpty != false)
            .help("Save Setlist (⌘S)")
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    @ViewBuilder
    private var setlist: some View {
        if let project = model.project, !project.sections.isEmpty {
            ScrollViewReader { proxy in
                List(selection: $selectedSectionID) {
                    ForEach(Array(project.sections.enumerated()), id: \.element.id) { index, section in
                        songRow(section, index: index, project: project)
                            .tag(section.id)
                            .id(section.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                            .listRowBackground(Color.clear)
                            .moveDisabled(!model.canReorder)
                    }
                    .onMove { model.moveSections(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .onChange(of: selectedSectionID) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Button("Open Setlist…") { model.openSetlist() }
                    .buttonStyle(.borderedProminent)
                Button("Select Logic Project…") { model.chooseProject() }
                    .buttonStyle(.bordered)
            }
            .disabled(!model.canReorder)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func songRow(_ section: ArrangementSection, index: Int, project: ImportedLogicProject) -> some View {
        let isLast = section.id == project.sections.last?.id
        return HStack(spacing: 10) {
            Text(String(format: "%02d", index + 1))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(section.name)
                .font(.system(size: 17, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("\(section.name) · \(MusicalTimeFormatter.position(tick: section.startTick, signatures: project.timeSignatures)) · \(MusicalTimeFormatter.duration(ticks: section.lengthTicks, startingAt: section.startTick, signatures: project.timeSignatures))")
            Button { editingSectionID = section.id } label: {
                Image(systemName: model.note(for: section).isEmpty ? "square.and.pencil" : "note.text")
                    .frame(width: 28, height: 32)
            }
            .buttonStyle(.borderless)
            .help("Edit note for \(section.name)")
            .popover(isPresented: Binding(
                get: { editingSectionID == section.id },
                set: { if !$0, editingSectionID == section.id { editingSectionID = nil } }
            )) {
                noteEditor(for: section)
            }
            HStack(spacing: 3) {
                Toggle("Stop", isOn: Binding(
                    get: { model.stopsAfter(section) },
                    set: { model.setStopsAfter($0, for: section) }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                .disabled(isLast || model.playlistAutomation.isTransitioning)
                .accessibilityLabel("Stop after \(section.name)")
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .opacity(isLast ? 1 : 0)
                    .accessibilityHidden(!isLast)
            }
            .frame(width: 66)
            .help(isLast ? "The final song always stops." : "Stop after this song and cue the next song ready for Play.")
        }
        .frame(height: 48)
        .contentShape(Rectangle())
    }

    private func noteEditor(for section: ArrangementSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(section.name).font(.headline).lineLimit(1)
                Spacer()
                Button("Done") { editingSectionID = nil }
            }
            TextField("Operator note…", text: Binding(
                get: { model.note(for: section) },
                set: { model.updateNote($0, for: section) }
            ), axis: .vertical)
            .lineLimit(5...10)
            .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var transport: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let previousSection { selectedSectionID = previousSection.id }
                } label: {
                    Label("Previous", systemImage: "backward.end.fill")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .disabled(previousSection == nil || !model.midiController.isReady)
                .help("Previous song (↑)")
                Button {
                    if let nextSection { selectedSectionID = nextSection.id }
                } label: {
                    Label("Next", systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .disabled(nextSection == nil || !model.midiController.isReady)
                .help("Next song (↓)")
            }
            .buttonStyle(.bordered)
            HStack(spacing: 10) {
                Button { model.playlistAutomation.manualStop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!model.midiController.isReady)
                .help("Stop playback (Space toggles Play/Stop)")
                Button { model.midiController.play() } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!model.midiController.isReady || model.playlistAutomation.isTransitioning)
                .help("Start playback (Space toggles Play/Stop)")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var statusFooter: some View {
        let progress = model.songProgress
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.midiController.isPlaying == nil ? Color.orange : .green)
                    .frame(width: 6, height: 6)
                    .help(model.midiController.status)
                Text(transportStateLabel)
                Spacer(minLength: 8)
                if model.midiController.clockMode == .smpte {
                    Button("Show Bars & Beats") { model.midiController.showBarsAndBeats() }
                        .buttonStyle(.link)
                } else {
                    Text(model.midiController.position?.label ?? "Waiting for position")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .lineLimit(1)
            HStack {
                Text(model.activeSection?.name ?? "No current song")
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(progress.map { "\($0.percentage)%" } ?? "—")
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            .font(.caption)
            ProgressView(value: progress?.fraction ?? 0)
                .tint(model.midiController.isPlaying == true ? .green : .accentColor)
                .accessibilityLabel("Song progress")
                .help(progress.map { "\($0.remainingDescription) remaining" } ?? "Waiting for song position")
            Text(model.playlistAutomation.status)
                .font(.caption2)
                .lineLimit(1)
                .help("\(model.playlistAutomation.status)\n\(model.midiController.status)" + (progress.map { "\n\($0.remainingDescription) remaining" } ?? ""))
        }
        .foregroundStyle(.secondary)
        .frame(height: 70, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.25))
    }

    private func handleKeyboardAction(_ action: OperatorKeyboardShortcuts.Action) {
        switch action {
        case .togglePlayback:
            if model.midiController.isPlaying == true || model.playlistAutomation.isTransitioning {
                model.playlistAutomation.manualStop()
            } else {
                model.midiController.play()
            }
        case .previousSong:
            if let previousSection { selectedSectionID = previousSection.id }
        case .nextSong:
            if let nextSection { selectedSectionID = nextSection.id }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private var previousSection: ArrangementSection? { adjacentSection(offset: -1) }
    private var nextSection: ArrangementSection? { adjacentSection(offset: 1) }

    private func adjacentSection(offset: Int) -> ArrangementSection? {
        guard let sections = model.project?.sections,
              let index = sections.firstIndex(where: { $0.id == selectedSectionID }),
              sections.indices.contains(index + offset) else { return nil }
        return sections[index + offset]
    }

    private var transportStateLabel: String {
        switch model.midiController.isPlaying {
        case .some(true): "Playing"
        case .some(false): "Stopped"
        case .none: "Waiting for Logic"
        }
    }

    private func ensureSelectedSection() {
        if let sectionID = model.playlistAutomation.armedSectionID,
           model.project?.sections.contains(where: { $0.id == sectionID }) == true,
           sectionID != selectedSectionID {
            suppressNextLocate = true
            selectedSectionID = sectionID
            return
        }
        guard let project = model.project,
              !project.sections.contains(where: { $0.id == selectedSectionID }) else { return }
        selectedSectionID = project.sections.first?.id
        suppressNextLocate = true
    }

}
