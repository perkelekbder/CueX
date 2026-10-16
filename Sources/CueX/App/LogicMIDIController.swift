import CoreMIDI
import CoreFoundation
import Foundation
import Observation
import Dispatch

extension Notification.Name {
    static let cueXLogicFeedbackReceived = Notification.Name("CueXLogicFeedbackReceived")
}

/// These Core MIDI callbacks run on its receive thread, outside the UI actor.
private func inspectMIDIEvent(_ context: UnsafeMutableRawPointer?, _ timestamp: MIDITimeStamp, _ message: MIDIUniversalMessage) {
    guard message.type == .channelVoice1, let context else { return }
    let voice = message.channelVoice1
    let updates = context.assumingMemoryBound(to: [MackieFeedbackEvent].self)
    if voice.status == .noteOn, voice.channel == 0,
       [0x5E, 0x71, 0x72].contains(voice.note.number) {
        updates.pointee.append(.note(number: voice.note.number, value: voice.note.velocity))
    } else if voice.status == .controlChange, [0, 15].contains(voice.channel),
              (0x40...0x49).contains(voice.controlChange.index) {
        updates.pointee.append(.display(index: Int(voice.controlChange.index - 0x40), value: voice.controlChange.data))
    }
}

private func receiveLogicMIDI(_ events: UnsafePointer<MIDIEventList>, _ sourceContext: UnsafeMutableRawPointer?) {
    var updates: [MackieFeedbackEvent] = []
    withUnsafeMutablePointer(to: &updates) {
        MIDIEventListForEachEvent(events, inspectMIDIEvent, $0)
    }
    guard !updates.isEmpty else { return }
    let batch = updates
    let receivedAt = ContinuousClock.now
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .cueXLogicFeedbackReceived, object: nil, userInfo: ["updates": batch, "receivedAt": receivedAt])
    }
}

/// A small Mackie Control transport surface exposed to Logic Pro over Core MIDI.
@Observable
@MainActor
final class LogicMIDIController {
    private(set) var status = "Starting MIDI…"
    private(set) var isPlaying: Bool?
    private(set) var position: MackieClockPosition?
    private(set) var clockMode: MackieClockMode = .unknown
    private(set) var positionReceivedAt: ContinuousClock.Instant?
    @ObservationIgnored var onFeedback: (@MainActor () -> Void)?
    @ObservationIgnored private var positionDecoder = MackiePositionDecoder()
    @ObservationIgnored private var positionUpdateTask: Task<Void, Never>?
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()
    private var playbackObserver: NSObjectProtocol?

    var isReady: Bool { source != 0 && destination != 0 }

    init() {
        playbackObserver = NotificationCenter.default.addObserver(
            forName: .cueXLogicFeedbackReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let updates = notification.userInfo?["updates"] as? [MackieFeedbackEvent] else { return }
            let receivedAt = notification.userInfo?["receivedAt"] as? ContinuousClock.Instant ?? .now
            MainActor.assumeIsolated { self?.consumeFeedback(updates, receivedAt: receivedAt) }
        }

        let clientStatus = MIDIClientCreateWithBlock("CueX" as CFString, &client, nil)
        guard clientStatus == noErr else {
            status = Self.errorText("Couldn’t create MIDI client", code: clientStatus)
            return
        }

        let sourceStatus = MIDISourceCreateWithProtocol(client, "CueX → Logic" as CFString, ._1_0, &source)
        guard sourceStatus == noErr else {
            status = Self.errorText("Couldn’t create CueX → Logic port", code: sourceStatus)
            dispose()
            return
        }

        let destinationStatus = MIDIDestinationCreateWithProtocol(
            client,
            "Logic → CueX" as CFString,
            ._1_0,
            &destination,
            receiveLogicMIDI
        )
        guard destinationStatus == noErr else {
            status = Self.errorText("Couldn’t create Logic → CueX port", code: destinationStatus)
            dispose()
            return
        }

        status = "MIDI ports ready · Enable MMC input in Logic for locating"
    }

    func play() { sendMackieButton(note: 0x5E) }
    func stop() { sendMackieButton(note: 0x5D) }

    func stopForPlaylist() {
        // MMC Stop is idempotent; unlike pressing MCU Stop twice it does not
        // jump to the beginning when a delayed acknowledgement requires a retry.
        let result = sendSystemExclusive([0xF0, 0x7F, 0x7F, 0x06, 0x01, 0xF7])
        if result != noErr { status = Self.errorText("Couldn’t send automatic stop", code: result) }
    }

    func showBarsAndBeats() {
        guard clockMode == .smpte else { return }
        sendMackieButton(note: 0x35)
    }

    private func consumeFeedback(_ updates: [MackieFeedbackEvent], receivedAt: ContinuousClock.Instant) {
        var clockChanged = false
        var transportChanged = false
        for update in updates {
            if case let .note(number: 0x5E, value: value) = update {
                isPlaying = value > 0
                transportChanged = true
            } else {
                positionDecoder.consume(update)
                clockChanged = true
            }
        }
        if transportChanged { onFeedback?() }
        guard clockChanged else { return }
        // One display refresh can arrive in several callbacks. Publish after
        // the burst so a digit carry doesn't briefly highlight the wrong song.
        positionUpdateTask?.cancel()
        positionUpdateTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(15)) } catch { return }
            guard let self else { return }
            self.clockMode = self.positionDecoder.mode
            self.position = self.positionDecoder.position
            self.positionReceivedAt = receivedAt
            self.onFeedback?()
        }
    }

    @discardableResult
    func locate(tick: Int, tempoChanges: [TempoChange], frameRate: Int?) -> Bool {
        guard source != 0 else { return false }
        guard let frameRate, [24, 25, 30].contains(frameRate) else {
            status = "Can’t locate: saved project frame rate is unsupported or unavailable"
            return false
        }
        guard let elapsed = Self.elapsedSeconds(at: tick, tempoChanges: tempoChanges) else {
            status = "Can’t locate: no readable tempo map in this project"
            return false
        }

        // The current importer assumes bar 1 is at 01:00:00:00. Send MMC
        // Locate (06 44), not an MTC Full Frame message (01 01).
        // Full-frame MMC locating must round forward, otherwise fractional-frame
        // song starts can land in the previous song. Precision is one SMPTE frame.
        let totalFrames = Int(((3_600 + elapsed) * Double(frameRate)).rounded(.up))
        let hour = totalFrames / (frameRate * 3_600)
        guard (0..<24).contains(hour) else {
            status = "Can’t locate: section is outside the supported timecode range"
            return false
        }
        let minute = (totalFrames / (frameRate * 60)) % 60
        let second = (totalFrames / frameRate) % 60
        let frame = totalFrames % frameRate
        let rateBits = frameRate == 24 ? 0 : (frameRate == 25 ? 0x20 : 0x60)
        let timecodeHour = UInt8(rateBits | hour)
        let result = sendSystemExclusive([
            0xF0, 0x7F, 0x7F, 0x06, 0x44, 0x06, 0x01,
            timecodeHour, UInt8(minute), UInt8(second), UInt8(frame), 0x00, 0xF7
        ])
        status = result == noErr
            ? "Locate sent · \(frameRate) fps"
            : Self.errorText("Couldn’t send locate", code: result)
        return result == noErr
    }

    private static func elapsedSeconds(at tick: Int, tempoChanges: [TempoChange]) -> Double? {
        guard tick >= 0,
              let first = tempoChanges.first,
              first.startTick == 0 else { return nil }
        var seconds = 0.0
        var cursorTick = 0
        var bpm = first.beatsPerMinute
        for change in tempoChanges.dropFirst() where change.startTick < tick {
            seconds += Double(change.startTick - cursorTick) / 960 * 60 / bpm
            cursorTick = change.startTick
            bpm = change.beatsPerMinute
        }
        seconds += Double(tick - cursorTick) / 960 * 60 / bpm
        return seconds
    }

    private func sendSystemExclusive(_ bytes: [UInt8]) -> OSStatus {
        // Keep this short SysEx in one MIDI 1.0 packet. This byte-based path was
        // verified against Logic's MMC input, including its SMPTE locate behavior.
        var list = MIDIPacketList()
        let packet = MIDIPacketListInit(&list)
        bytes.withUnsafeBufferPointer { buffer in
            _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size,
                                 packet, mach_absolute_time(), buffer.count, buffer.baseAddress!)
        }
        return MIDIReceived(source, &list)
    }

    private func sendMackieButton(note: UInt8) {
        guard source != 0 else { return }

        // Mackie Control transport buttons are momentary: send Note On followed
        // immediately by Note Off. UMP MIDI 1.0 words contain status/data bytes.
        let words: [UInt32] = [
            0x2090_0000 | (UInt32(note) << 8) | 0x7F,
            0x2080_0000 | (UInt32(note) << 8)
        ]
        let capacity = 128
        let rawList = UnsafeMutableRawPointer.allocate(
            byteCount: capacity,
            alignment: MemoryLayout<MIDIEventList>.alignment
        )
        defer { rawList.deallocate() }
        let list = rawList.assumingMemoryBound(to: MIDIEventList.self)
        var packet = MIDIEventListInit(list, ._1_0)
        let timestamp = mach_absolute_time()

        for word in words {
            var eventWord = word
            packet = withUnsafePointer(to: &eventWord) { wordPointer in
                MIDIEventListAdd(list, capacity, packet, timestamp, 1, wordPointer)
            }
        }
        _ = MIDIReceivedEventList(source, list)
    }

    private func dispose() {
        if let playbackObserver {
            NotificationCenter.default.removeObserver(playbackObserver)
            self.playbackObserver = nil
        }
        if destination != 0 {
            MIDIEndpointDispose(destination)
            destination = 0
        }
        if source != 0 {
            MIDIEndpointDispose(source)
            source = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
    }

    private static func errorText(_ message: String, code: OSStatus) -> String {
        "\(message) (Core MIDI error \(code))"
    }
}
