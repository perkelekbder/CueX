import Foundation

enum MusicalTimeFormatter {
    /// The MCU clock gives a reliable bar/beat independently of Logic's
    /// configurable division grid. Resolve that beat through the meter map.
    static func beatRange(bar targetBar: Int, beat: Int, signatures: [TimeSignature]) -> Range<Int>? {
        let ordered = signatures.sorted { $0.startTick < $1.startTick }
        guard targetBar > 0, beat > 0, let first = ordered.first else { return nil }
        var current = signature(at: 0, in: ordered, fallback: first)
        var startTick = 0
        var startBar = 1
        for change in ordered where change.startTick > 0 {
            guard current.barTicks > 0 else { return nil }
            let changeBar = startBar + (change.startTick - startTick) / current.barTicks
            if targetBar < changeBar { break }
            startBar = changeBar
            startTick = change.startTick
            current = change
        }
        guard beat <= current.numerator, current.beatTicks > 0 else { return nil }
        let tick = startTick + (targetBar - startBar) * current.barTicks + (beat - 1) * current.beatTicks
        return tick..<(tick + current.beatTicks)
    }

    static func barNumber(tick: Int, signatures: [TimeSignature]) -> Int? {
        guard tick >= 0 else { return nil }
        return musicalPosition(tick: tick, signatures: signatures)?.bar
    }

    static func position(tick: Int, signatures: [TimeSignature]) -> String {
        guard tick >= 0, let position = musicalPosition(tick: tick, signatures: signatures) else {
            return "—"
        }
        if position.beat == 1 && position.beatRemainderTicks == 0 {
            return "Bar \(position.bar)"
        }
        let remainder = position.beatRemainderTicks == 0 ? "" : " + \(position.beatRemainderTicks) ticks"
        return "Bar \(position.bar), Beat \(position.beat)\(remainder)"
    }

    static func duration(ticks: Int, startingAt startTick: Int, signatures: [TimeSignature]) -> String {
        guard ticks >= 0 else { return "—" }
        guard !signatures.isEmpty else { return quarterNotes(ticks) }
        if ticks == 0 { return "0 bars" }

        let endTick = startTick + ticks
        var cursor = startTick
        var segments: [(ticks: Int, signature: TimeSignature)] = []
        while cursor < endTick {
            let signature = signature(at: cursor, in: signatures)
            let nextChange = signatures
                .map(\.startTick)
                .filter { $0 > cursor && $0 < endTick }
                .min() ?? endTick
            let segmentEnd = min(nextChange, endTick)
            guard segmentEnd > cursor else { break }
            segments.append((segmentEnd - cursor, signature))
            cursor = segmentEnd
        }

        let descriptions = segments.compactMap { segment -> String? in
            let barTicks = segment.signature.barTicks
            let beatTicks = segment.signature.beatTicks
            guard barTicks > 0, beatTicks > 0 else { return nil }
            let bars = segment.ticks / barTicks
            let afterBars = segment.ticks % barTicks
            let beats = afterBars / beatTicks
            let extraTicks = afterBars % beatTicks
            var pieces: [String] = []
            if bars > 0 { pieces.append("\(bars) \(bars == 1 ? "bar" : "bars")") }
            if beats > 0 { pieces.append("\(beats) \(beats == 1 ? "beat" : "beats")") }
            if extraTicks > 0 { pieces.append("\(extraTicks) ticks") }
            if pieces.isEmpty { pieces.append("0 bars") }
            return "\(pieces.joined(separator: " + ")) (\(segment.signature.label))"
        }
        return descriptions.isEmpty ? quarterNotes(ticks) : descriptions.joined(separator: " + ")
    }

    private static func musicalPosition(tick: Int, signatures: [TimeSignature]) -> MusicalPosition? {
        guard let first = signatures.sorted(by: { $0.startTick < $1.startTick }).first else { return nil }
        let ordered = signatures.sorted(by: { $0.startTick < $1.startTick })
        var currentSignature = signature(at: 0, in: ordered, fallback: first)
        var segmentStart = 0
        var bar = 1

        for change in ordered where change.startTick > 0 && change.startTick <= tick {
            guard currentSignature.barTicks > 0 else { return nil }
            bar += max(0, (change.startTick - segmentStart) / currentSignature.barTicks)
            segmentStart = change.startTick
            currentSignature = change
        }

        guard currentSignature.barTicks > 0, currentSignature.beatTicks > 0 else { return nil }
        let offset = tick - segmentStart
        bar += offset / currentSignature.barTicks
        let withinBar = offset % currentSignature.barTicks
        return MusicalPosition(
            bar: bar,
            beat: withinBar / currentSignature.beatTicks + 1,
            beatRemainderTicks: withinBar % currentSignature.beatTicks
        )
    }

    private static func signature(at tick: Int, in signatures: [TimeSignature]) -> TimeSignature {
        let ordered = signatures.sorted(by: { $0.startTick < $1.startTick })
        return signature(at: tick, in: ordered, fallback: ordered.first ?? TimeSignature(startTick: 0, numerator: 4, denominator: 4))
    }

    private static func signature(at tick: Int, in signatures: [TimeSignature], fallback: TimeSignature) -> TimeSignature {
        signatures.last(where: { $0.startTick <= tick }) ?? fallback
    }

    private static func quarterNotes(_ ticks: Int) -> String {
        let value = Double(ticks) / 960
        let formatted = value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
        return "\(formatted) quarter notes"
    }
}
