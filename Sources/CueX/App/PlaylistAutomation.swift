import Foundation
import Observation

@Observable
@MainActor
final class PlaylistAutomation {
    private(set) var status = "Last song always stops"
    private(set) var armedSectionID: String?
    private(set) var setFinishedAt: Date?
    private(set) var isTransitioning = false
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
        armedSectionID = nil
        status = "Last song always stops"
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
        guard let project else { return }
        setFinishedAt = nil
        cancelResume()
        cancelRun()
        retryTask?.cancel()
        transition.reset()
        clearManualStopRequest()
        armedSectionID = nil
        status = sendLocate(section, in: project) ? "Ready: \(section.name)" : "Stopped: couldn’t cue \(section.name)"
    }

    func manualPlay() {
        setFinishedAt = nil
        clearManualStopRequest()
        midi.play()
    }

    func manualStop() {
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
        if midi.isPlaying == true { setFinishedAt = nil }
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
        if returnedToProjectStart, transition.pending == nil, pendingResume == nil {
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
                    // Stop has been acknowledged. Cue exactly once, keeping the
                    // transport stopped; the view follows armedSectionID.
                    let sentAt = ContinuousClock.now
                    guard sendLocate(next, in: project) else {
                        status = "Stopped: couldn’t cue \(next.name)"
                        return
                    }
                    armedSectionID = next.id
                    status = "Ready: \(next.name)"
                    if completion.boundary.continuesAutomatically {
                        pendingResume = (next.id, sentAt)
                        isTransitioning = true
                        status = "Cueing: \(next.name)"
                        resumeTask = Task { @MainActor [weak self] in
                            do { try await Task.sleep(for: .seconds(2)) } catch { return }
                            guard let self, self.pendingResume != nil else { return }
                            self.cancelResume()
                            self.midi.stopForPlaylist()
                            self.status = "Stopped: next song position wasn’t confirmed"
                        }
                    }
                } else {
                    setFinishedAt = .now
                    status = "Set finished · Logic stopped"
                }
            }
            return
        }

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
