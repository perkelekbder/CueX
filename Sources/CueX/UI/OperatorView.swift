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
                panelDivider
                SetTimingHeader(model: model, fallbackSectionID: selectedSectionID)
                panelDivider
                setlist
                panelDivider
                transport
                panelDivider
                statusFooter
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LogicTheme.background)
        }
        .frame(minWidth: 360, minHeight: 560)
        .foregroundStyle(LogicTheme.text)
        .tint(LogicTheme.blue)
        .preferredColorScheme(.dark)
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
            if let oldID = selectedSectionID, let newID = model.reloadedSectionIDs[oldID], newID != oldID {
                suppressNextLocate = true
                selectedSectionID = newID
            }
            ensureSelectedSection()
        }
        .onChange(of: selectedSectionID) { _, sectionID in
            if suppressNextLocate {
                suppressNextLocate = false
                return
            }
            guard let section = model.project?.sections.first(where: { $0.id == sectionID }) else { return }
            // Excluded rows remain selectable for dragging, but never locate.
            guard model.project?.isExcluded(section.id) != true else { return }
            model.locate(section)
        }
        .onChange(of: model.playlistAutomation.armedSectionID) { _, sectionID in
            guard let sectionID, sectionID != selectedSectionID else { return }
            // The automation already located this song after Stop was confirmed.
            suppressNextLocate = true
            selectedSectionID = sectionID
        }
    }

    private var panelDivider: some View {
        Rectangle().fill(LogicTheme.divider).frame(height: 1)
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
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .help("Open, save, or reload a setlist")
            Menu {
                Button("Add Pause") { model.addPause(after: selectedSectionID) }
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.project == nil || !model.canReorder)
            .help("Add a pause after the selected row, then drag it into place")
            Button { model.saveSetlist() } label: {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(model.project?.sections.isEmpty != false)
            .help("Save Setlist (⌘S)")
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .tint(.white)
        .foregroundStyle(.white)
        .background(LogicTheme.toolbar)
    }

    @ViewBuilder
    private var setlist: some View {
        if let project = model.project, !project.sections.isEmpty {
            ScrollViewReader { proxy in
                List(selection: $selectedSectionID) {
                    ForEach(Array(project.sections.enumerated()), id: \.element.id) { index, section in
                        setlistRow(section, index: index, project: project)
                            .opacity(project.isExcluded(section.id) ? 0.35 : 1)
                            .tag(section.id)
                            .id(section.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                            .listRowBackground(selectedSectionID == section.id ? LogicTheme.selectedRow : LogicTheme.row)
                            .moveDisabled(!model.canReorder)
                    }
                    .onMove { model.moveSections(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(LogicTheme.setlist)
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
            .background(LogicTheme.setlist)
        }
    }

    @ViewBuilder
    private func setlistRow(_ section: ArrangementSection, index: Int, project: ImportedLogicProject) -> some View {
        if section.isSong {
            songRow(section, index: index, project: project)
        } else {
            blockRow(section, index: index)
                .contextMenu {
                    if !section.isFullStop {
                        Button("Edit Pause…") { editingSectionID = section.id }
                        Button("Remove Pause", role: .destructive) { model.removeBlock(section) }
                            .disabled(!model.canReorder)
                    }
                }
        }
    }

    private func blockRow(_ section: ArrangementSection, index: Int) -> some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", index + 1))
                .font(.caption.monospacedDigit())
                .foregroundStyle(LogicTheme.secondaryText)
                .frame(width: 24)
            Image(systemName: section.isFullStop ? "stop.circle.fill" : "timer")
                .foregroundStyle(section.isFullStop ? LogicTheme.red : LogicTheme.amber)
            Text(section.name)
                .font(.system(size: 17, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            if section.isFullStop {
                Toggle("Stop", isOn: .constant(true))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .disabled(true)
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(LogicTheme.secondaryText)
            } else {
                Button {
                    editingSectionID = section.id
                } label: {
                    HStack(spacing: 5) {
                        Text("\(section.block?.seconds ?? 0) s").monospacedDigit()
                        Image(systemName: "pencil")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(!model.canReorder)
                .help("Edit pause length in seconds")
                .popover(isPresented: Binding(
                    get: { editingSectionID == section.id },
                    set: { if !$0 { editingSectionID = nil } }
                )) {
                    PauseBlockEditor(model: model, section: section) { editingSectionID = nil }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background((section.isFullStop ? LogicTheme.red : LogicTheme.amber).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .help(section.isFullStop
              ? "The set ends here. Rows below are excluded from playback and timing. Drag rows above this block to enable them again."
              : "Stops Logic, waits for the chosen number of seconds, then automatically starts the next song. Stop cancels the countdown.")
    }

    private func songRow(_ section: ArrangementSection, index: Int, project: ImportedLogicProject) -> some View {
        let progress: SongProgress? = selectedSectionID == section.id
            ? model.songProgress.flatMap { $0.section.id == section.id ? $0 : nil } : nil
        return HStack(spacing: 10) {
            Text(String(format: "%02d", index + 1))
                .font(.caption.monospacedDigit())
                .foregroundStyle(LogicTheme.secondaryText)
                .frame(width: 24)
            Text(section.name)
                .font(.system(size: 17, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("\(section.name) · \(MusicalTimeFormatter.position(tick: section.startTick, signatures: project.timeSignatures)) · \(MusicalTimeFormatter.duration(ticks: section.lengthTicks, startingAt: section.startTick, signatures: project.timeSignatures))")
            Text(model.songDurationLabel(for: section))
                .font(.caption.monospacedDigit())
                .foregroundStyle(LogicTheme.secondaryText)
                .fixedSize()
                .frame(minWidth: 38, alignment: .trailing)
                .accessibilityLabel("Song duration: \(model.songDurationLabel(for: section))")
                .help(model.setlistDurations?.songSeconds[section.id] == nil
                      ? "Duration unavailable: this song has no usable saved tempo map."
                      : "Song duration including saved tempo changes; hours appear for durations of one hour or longer.")
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
                .disabled(model.playlistAutomation.isTransitioning)
                .accessibilityLabel("Stop after \(section.name)")
            }
            .frame(width: 66)
            .help("Stop after this song and cue the next song ready for Play. Full Stop always ends the set.")
        }
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            if selectedSectionID == section.id, !project.isExcluded(section.id) {
                ProgressView(value: progress?.fraction ?? 0)
                    .progressViewStyle(.linear)
                    .tint(model.midiController.isPlaying == true ? LogicTheme.green : LogicTheme.blue)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("\(section.name) progress")
                    .accessibilityValue(progress.map { "\($0.percentage)%" } ?? "Waiting for song position")
                    .help(progress.map { "\($0.percentage)% · \($0.remainingDescription) remaining" }
                          ?? "Waiting for this song’s position from Logic")
            }
        }
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
        .background(LogicTheme.panel)
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
            .buttonStyle(LogicButtonStyle())
            HStack(spacing: 10) {
                Button { model.playlistAutomation.manualStop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(LogicButtonStyle(cornerRadius: 14))
                .disabled(!model.midiController.isReady)
                .help("Stop playback (Space toggles Play/Stop)")
                Button { model.playlistAutomation.manualPlay(sectionID: selectedSectionID) } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(LogicButtonStyle(tint: LogicTheme.blue, cornerRadius: 14))
                .disabled(!canPlaySelection)
                .help("Start playback (Space toggles Play/Stop)")
            }
        }
        .padding(12)
        .fixedSize(horizontal: false, vertical: true)
        .background(LogicTheme.panel)
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            LogicConnectionIndicator(midi: model.midiController)
            HStack(spacing: 6) {
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
            if let notice = model.projectChangeNotice {
                Button { model.handleProjectChangeNotice() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.hasPendingProjectReload ? "exclamationmark.triangle" : "checkmark.circle")
                        Text(notice).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: model.hasPendingProjectReload ? "arrow.clockwise" : "xmark")
                    }
                    .font(.caption2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.hasPendingProjectReload ? LogicTheme.amber : LogicTheme.secondaryText)
                .help(notice + (model.hasPendingProjectReload ? "\nReloads automatically once stopped. Click to retry while stopped." : "\nClick to dismiss."))
            }
        }
        .foregroundStyle(LogicTheme.secondaryText)
        .frame(height: 52, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LogicTheme.footer)
    }

    private func handleKeyboardAction(_ action: OperatorKeyboardShortcuts.Action) {
        switch action {
        case .togglePlayback:
            if model.midiController.isPlaying == true || model.playlistAutomation.isTransitioning {
                model.playlistAutomation.manualStop()
            } else if canPlaySelection {
                model.playlistAutomation.manualPlay(sectionID: selectedSectionID)
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

    private var canPlaySelection: Bool {
        guard model.canStartPlayback, let project = model.project,
              let selected = project.sections.first(where: { $0.id == selectedSectionID }) else { return false }
        return project.canCue(selected)
    }

    private var previousSection: ArrangementSection? { adjacentSection(offset: -1) }
    private var nextSection: ArrangementSection? { adjacentSection(offset: 1) }

    private func adjacentSection(offset: Int) -> ArrangementSection? {
        guard let sections = model.project?.sections.filter({ model.project?.isExcluded($0.id) != true }),
              let index = sections.firstIndex(where: { $0.id == selectedSectionID }),
              sections.indices.contains(index + offset) else { return nil }
        return sections[index + offset]
    }

    private var transportStateLabel: String {
        if model.playlistAutomation.pauseSectionID != nil { return "Pause countdown" }
        return switch model.midiController.isPlaying {
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
              !project.sections.contains(where: { $0.id == selectedSectionID && !project.isExcluded($0.id) }) else { return }
        selectedSectionID = project.sections.first?.id
        suppressNextLocate = true
    }

}

private struct PauseBlockEditor: View {
    let model: CueXModel
    let section: ArrangementSection
    let done: () -> Void
    @State private var seconds: Int

    init(model: CueXModel, section: ArrangementSection, done: @escaping () -> Void) {
        self.model = model
        self.section = section
        self.done = done
        _seconds = State(initialValue: section.block?.seconds ?? 30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pause length").font(.headline)
            HStack {
                TextField("Seconds", value: $seconds, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(apply)
                Text("seconds")
                Stepper("Seconds", value: $seconds, in: 1...86_400)
                    .labelsHidden()
            }
            Text("Logic stops during the pause, then starts the next song automatically.")
                .font(.caption)
                .foregroundStyle(LogicTheme.secondaryText)
            HStack {
                Button("Cancel", action: done)
                Spacer()
                Button("Apply", action: apply)
                    .buttonStyle(.borderedProminent)
                    .disabled(!(1...86_400).contains(seconds) || !model.canReorder)
            }
        }
        .padding(16)
        .frame(width: 290)
        .background(LogicTheme.panel)
    }

    private func apply() {
        guard (1...86_400).contains(seconds), model.canReorder else { return }
        model.updatePause(seconds, for: section)
        done()
    }
}
