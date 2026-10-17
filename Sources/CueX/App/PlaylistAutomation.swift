import Foundation
import Observation

@Observable
@MainActor
final class PlaylistAutomation {
    private(set) var status = "Full stop marks the end of the set"
    private(set) var armedSectionID: String?
    private(set) var setFinishedAt: Date?
    private(set) var isTransitioning = false
    private(set) var pauseSectionID: String?
    @ObservationIgnored private var pauseDeadline: ContinuousClock.Instant?
    @ObservationIgnored private var pauseTask: Task<Void, Never>?

    var pauseRemainingSeconds: Double? {
        guard let pauseDeadline else { return nil }
        let remaining = ContinuousClock.now.duration(to: pauseDeadline).components
        return max(0, Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18)
    }
    var cueingSectionID: String? { pendingResume?.sectionID }

    @ObservationIgnored private var pendingResume: (sectionID: String, sentAt: ContinuousClock.Instant)?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private let midi: LogicMIDIController
    @ObservationIgnored private var project: ImportedLogicProject?
    @ObservationIgnored private var savedIDs: Set<String> = []
    @ObservationIgnored private var transition = PlaylistStopTransition()
    @ObservationIgnored private var target: PlaylistStopBoundary?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var startedAt: ContinuousClock.Instant?
    @ObservationIgnored private var lastSample: ContinuousClock.Instant?
    @ObservationIgnored private var previousBeat: Int?
    @ObservationIgnored private var lastReportedSectionID: String?
    @ObservationIgnored private var lastReportedPositionAt: ContinuousClock.Instant?
    @ObservationIgnored private var lastLocateSentAt: ContinuousClock.Instant?
    @ObservationIgnored private var wasPlaying = false
    @ObservationIgnored private var projectStartGuard = ProjectStartReturnGuard()
    @ObservationIgnored private var manualStopAwaitingAcknowledgement = false
    @ObservationIgnored private var returnToStartAfterManualStop = false

    init(midi: LogicMIDIController) {
        self.midi = midi
        midi.onFeedback = { [weak self] in self?.receiveFeedback() }
    }

    func configure(project: ImportedLogicProject, savedIDs: Set<String>) {
        cancelResume()
        cancelRun()
        transition.reset()
        retryTask?.cancel()
        self.project = project
        setFinishedAt = nil
        self.savedIDs = savedIDs
        clearManualStopRequest()
        projectStartGuard.reset(position: midi.position, receivedAt: midi.positionReceivedAt)
        lastReportedSectionID = midi.position.flatMap { project.section(at: $0)?.id }
        lastReportedPositionAt = midi.positionReceivedAt
        lastLocateSentAt = nil
        armedSectionID = nil
        status = "Full stop marks the end of the set"
        receiveFeedback()
    }

    func updateOptions(_ savedIDs: Set<String>) {
        self.savedIDs = savedIDs
        target = nil
        stopTask?.cancel()
        stopTask = nil
        lastSample = nil
        receiveFeedback()
    }

    func manualLocate(_ section: ArrangementSection) {
        guard let project, !project.isExcluded(section.id) else { return }
        setFinishedAt = nil
        cancelResume()
        cancelRun()
        retryTask?.cancel()
        transition.reset()
        clearManualStopRequest()
        armedSectionID = section.id
        if !section.isSong {
            midi.stopForPlaylist()
            status = section.isFullStop ? "Full stop · Playback ends here" : "Ready: Pause · Press Play to start countdown"
            return
        }
        status = sendLocate(section, in: project) ? "Ready: \(section.name)" : "Stopped: couldn’t cue \(section.name)"
    }

    func manualPlay(sectionID: String? = nil) {
        guard let project else { return }
        let entry = project.sections.first(where: { $0.id == (sectionID ?? armedSectionID) })
            ?? midi.position.flatMap { project.section(at: $0) }
            ?? project.playableEntries.first
        guard let entry, project.canCue(entry), !isTransitioning else { return }
        setFinishedAt = nil
        clearManualStopRequest()
        if !entry.isSong {
            guard midi.isPlaying == false else {
                midi.stopForPlaylist()
                status = "Stop Logic before starting a pause"
                return
            }
            beginEntry(entry, automatically: true)
        } else {
            // A reorder/import can leave Logic at a different row. Confirm the
            // chosen song before starting instead of playing that old position.
            if midi.position.flatMap({ project.section(at: $0) })?.id != entry.id {
                guard midi.isPlaying == false else {
                    midi.stopForPlaylist()
                    status = "Stop Logic before cueing the selected song"
                    return
                }
                beginEntry(entry, automatically: true)
            } else {
                armedSectionID = entry.id
                midi.play()
            }
        }
    }

    func manualStop() {
        if pauseSectionID != nil {
            cancelResume()
            cancelRun()
            clearManualStopRequest()
            midi.stopForPlaylist()
            status = "Pause canceled · Press Play to restart the pause"
            return
        }
        // The second click can precede Logic's acknowledgement of the first.
        let returnToStart = midi.isPlaying == false || manualStopAwaitingAcknowledgement
        manualStopAwaitingAcknowledgement = midi.isPlaying != false
        returnToStartAfterManualStop = returnToStart
        cancelResume()
        cancelRun()
        retryTask?.cancel()
        transition.reset()
        status = "Stopped by operator"
        midi.stopForPlaylist()
        if midi.isPlaying == false { cueSetlistStart() }
    }

    private func clearManualStopRequest() {
        manualStopAwaitingAcknowledgement = false
        returnToStartAfterManualStop = false
    }

    private func sendLocate(_ section: ArrangementSection, in project: ImportedLogicProject) -> Bool {
        let sentAt = ContinuousClock.now
        guard midi.locate(tick: section.startTick, tempoChanges: project.tempoChanges, frameRate: project.timecodeFrameRate) else { return false }
        projectStartGuard.didLocate(tick: section.startTick, sentAt: sentAt)
        lastLocateSentAt = sentAt
        return true
    }

    private func cueSetlistStart() {
        guard let project, let first = project.sections.first else { return }
        setFinishedAt = nil
        cancelResume()
        cancelRun()
        retryTask?.cancel()
        transition.reset()
        clearManualStopRequest()
        if !first.isSong {
            armedSectionID = first.id
            status = first.isFullStop ? "Full stop · No songs enabled" : "Ready: Pause · Setlist start"
            return
        }
        guard sendLocate(first, in: project) else {
            status = "Stopped: couldn’t cue the setlist start"
            return
        }
        armedSectionID = first.id
        status = "Ready: \(first.name) · Setlist start"
    }

    private func receiveFeedback() {
        guard let project else { return }
        if midi.isPlaying == nil {
            // A closed/restarted Logic session must not retain an old pending
            // automatic stop or restart. Fresh feedback will start a new run.
            cancelResume()
            cancelRun()
            retryTask?.cancel()
            transition.reset()
            clearManualStopRequest()
            armedSectionID = nil
            status = "Waiting for Logic transport"
            return
        }
        if midi.isPlaying == true {
            if pauseSectionID != nil || setFinishedAt != nil
                || midi.position.flatMap({ project.section(at: $0) }).map({ project.isExcluded($0.id) }) == true {
                cancelResume()
                cancelRun()
                transition.reset()
                midi.stopForPlaylist()
                status = "Stopped: playback outside the enabled set"
                return
            }
        }
        let returnedToProjectStart = projectStartGuard.observe(
            position: midi.position, receivedAt: midi.positionReceivedAt, isPlaying: midi.isPlaying)
        if midi.isPlaying == false, manualStopAwaitingAcknowledgement {
            let shouldReturn = returnToStartAfterManualStop
            clearManualStopRequest()
            if shouldReturn {
                cueSetlistStart()
                return
            }
        }
        if returnedToProjectStart, transition.pending == nil, pendingResume == nil, pauseSectionID == nil {
            cueSetlistStart()
            return
        }
        if let completion = transition.acknowledge(isPlaying: midi.isPlaying) {
            cancelRun()
            retryTask?.cancel()
            isTransitioning = false
            if completion.armNext {
                if let nextID = completion.boundary.nextSectionID,
                   let next = project.sections.first(where: { $0.id == nextID }) {
                    beginEntry(next, automatically: completion.boundary.continuesAutomatically)
                } else {
                    setFinishedAt = .now
                    status = "Set finished · Logic stopped"
                }
            }
            return
        }

        if pauseSectionID != nil { return }

        if let resume = pendingResume {
            if let receivedAt = midi.positionReceivedAt, receivedAt > resume.sentAt,
               let position = midi.position,
               project.section(at: position)?.id == resume.sectionID {
                cancelResume()
                if midi.isPlaying == false { midi.play() }
            } else {
                return
            }
        }

        followReportedSong(in: project)

        guard midi.isPlaying == true else {
            cancelRun()
            return
        }
        if !wasPlaying {
            wasPlaying = true
            startedAt = .now
            lastSample = nil
            refreshWatchdog()
        }
        guard transition.pending == nil,
              let position = midi.position, let receivedAt = midi.positionReceivedAt,
              let startedAt, receivedAt >= startedAt, receivedAt != lastSample else { return }
        lastSample = receivedAt
        refreshWatchdog()
        guard let beat = MusicalTimeFormatter.beatRange(bar: position.bar, beat: position.beat, signatures: project.timeSignatures) else {
            failClosed("Stopped: musical position unavailable")
            return
        }

        if let previousBeat, beat.lowerBound < previousBeat {
            target = nil
            stopTask?.cancel()
            stopTask = nil
        }
        previousBeat = beat.lowerBound
        if target == nil {
            target = PlaylistStopPolicy.nextBoundary(from: beat.lowerBound, project: project, savedIDs: savedIDs)
        }
        guard let target else { return }
        if beat.lowerBound >= target.endTick {
            requestStop(target, armNext: true)
            return
        }
        status = target.continuesAutomatically
            ? "Continues to next song after: \(target.sectionName)"
            : "Stops after: \(target.sectionName)"

        // Division 1 has a known offset regardless of Logic's division grid:
        // the one-based tick field is measured from this beat's beginning.
        guard position.division == 1, position.tick > 0, position.tick <= beat.count else {
            if stopTask == nil, beat.upperBound >= target.endTick {
                failClosed("Stopped: boundary timing unavailable")
            }
            return
        }
        let tick = beat.lowerBound + position.tick - 1
        guard let seconds = MusicalTimeline.seconds(from: tick, to: max(tick, target.endTick), tempos: project.tempoChanges) else {
            failClosed("Stopped: tempo map unavailable")
            return
        }
        let age = receivedAt.duration(to: .now)
        let ageSeconds = Double(age.components.seconds) + Double(age.components.attoseconds) / 1e18
        // A small lead allows MIDI delivery before the boundary instead of
        // waiting for a clock message from the following song or project tail.
        let delay = seconds - ageSeconds - 0.030
        stopTask?.cancel()
        if delay <= 0 {
            requestStop(target, armNext: true)
        } else {
            stopTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, self.target == target, self.midi.isPlaying == true else { return }
                self.requestStop(target, armNext: true)
            }
        }
    }

    private func followReportedSong(in project: ImportedLogicProject) {
        guard !isTransitioning,
              let receivedAt = midi.positionReceivedAt,
              lastReportedPositionAt.map({ receivedAt > $0 }) ?? true,
              lastLocateSentAt.map({ receivedAt > $0 }) ?? true,
              let position = midi.position else { return }
        let section = project.section(at: position)
        let changed = section?.id != lastReportedSectionID
        lastReportedPositionAt = receivedAt
        lastReportedSectionID = section?.id
        guard changed, let section, !project.isExcluded(section.id) else { return }

        // A forward seek can also leave the old song's stop timer behind.
        // Recalculate from the reported song before scheduling another stop.
        target = nil
        stopTask?.cancel()
        stopTask = nil
        setFinishedAt = nil
        armedSectionID = section.id
        if midi.isPlaying == false { status = "Ready: \(section.name)" }
        // The view follows armedSectionID without sending a locate back to Logic.
    }

    // Called only with Logic stopped: blocks never send synthetic locate positions.
    private func beginEntry(_ entry: ArrangementSection, automatically: Bool) {
        guard let project else { return }
        cancelResume()
        armedSectionID = entry.id
        if entry.isFullStop || project.isExcluded(entry.id) {
            setFinishedAt = .now
            status = "Full stop · Set finished"
            return
        }
        if let block = entry.block {
            pauseSectionID = entry.id
            pauseDeadline = .now.advanced(by: .seconds(block.seconds))
            isTransitioning = true
            status = "Pause · \(block.seconds) seconds · Stop cancels countdown"
            pauseTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(block.seconds)) } catch { return }
                guard let self, self.pauseSectionID == entry.id else { return }
                guard self.midi.isReady, self.midi.isPlaying == false else {
                    self.cancelResume()
                    self.status = "Pause ended · Logic unavailable · Press Play to retry"
                    return
                }
                self.advanceAfterPause(entry)
            }
            return
        }
        let sentAt = ContinuousClock.now
        guard sendLocate(entry, in: project) else {
            status = "Stopped: couldn’t cue \(entry.name)"
            return
        }
        status = "Ready: \(entry.name)"
        guard automatically else { return }
        pendingResume = (entry.id, sentAt)
        isTransitioning = true
        status = "Cueing: \(entry.name)"
        resumeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, self.pendingResume != nil else { return }
            self.cancelResume()
            self.midi.stopForPlaylist()
            self.status = "Stopped: next song position wasn’t confirmed"
        }
    }

    private func advanceAfterPause(_ entry: ArrangementSection) {
        guard let project, let index = project.sections.firstIndex(where: { $0.id == entry.id }) else { return }
        cancelResume()
        if project.sections.indices.contains(index + 1) {
            beginEntry(project.sections[index + 1], automatically: true)
        } else {
            setFinishedAt = .now
            status = "Set finished · Logic stopped"
        }
    }

    private func requestStop(_ boundary: PlaylistStopBoundary, armNext: Bool) {
        guard transition.request(boundary, armNext: armNext) else { return }
        isTransitioning = true
        stopTask?.cancel()
        stopTask = nil
        watchdogTask?.cancel()
        if armNext { status = "Stopping after: \(boundary.sectionName)" }
        midi.stopForPlaylist()
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            for _ in 0..<5 {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.transition.pending != nil else { return }
                self.midi.stopForPlaylist()
            }
            guard let self, self.transition.pending != nil else { return }
            self.status = "Stop sent · Waiting for Logic confirmation"
        }
    }

    private func failClosed(_ message: String) {
        guard let project,
              let boundary = target ?? PlaylistStopPolicy.nextBoundary(from: 0, project: project, savedIDs: savedIDs) else { return }
        status = message
        requestStop(boundary, armNext: false)
    }

    private func refreshWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            guard let self, self.midi.isPlaying == true, self.transition.pending == nil else { return }
            self.failClosed("Stopped: Logic position feedback was lost")
        }
    }

    private func cancelResume() {
        pauseTask?.cancel()
        pauseTask = nil
        pauseDeadline = nil
        pauseSectionID = nil
        resumeTask?.cancel()
        resumeTask = nil
        pendingResume = nil
        isTransitioning = false
    }

    private func cancelRun() {
        stopTask?.cancel()
        stopTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        target = nil
        previousBeat = nil
        lastSample = nil
        startedAt = nil
        wasPlaying = false
    }
}
