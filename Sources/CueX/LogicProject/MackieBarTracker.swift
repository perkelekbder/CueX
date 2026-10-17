import Foundation

/// Logic's MCU Beats display reports only the last three bar digits.
/// An explicit CueX locate anchors the full bar; subsequent nearby positions
/// follow that anchor, including 999 → 1000 and the reverse direction.
struct MackieBarTracker {
    private(set) var referenceBar: Int?

    mutating func didLocate(bar: Int) {
        referenceBar = bar
    }

    func resolved(_ raw: MackieClockPosition) -> MackieClockPosition? {
        guard (0..<1_000).contains(raw.bar) else { return nil }
        let bar: Int
        if let referenceBar {
            let base = referenceBar / 1_000 * 1_000
            let candidates = [base - 1_000, base, base + 1_000]
                .map { $0 + raw.bar }.filter { $0 > 0 }
            let ordered = candidates.sorted { abs($0 - referenceBar) < abs($1 - referenceBar) }
            guard let nearest = ordered.first,
                  ordered.count < 2 || abs(ordered[1] - referenceBar) != abs(nearest - referenceBar) else { return nil }
            bar = nearest
        } else {
            guard raw.bar > 0 else { return nil }
            bar = raw.bar
        }
        return MackieClockPosition(bar: bar, beat: raw.beat, division: raw.division, tick: raw.tick)
    }

    mutating func accept(_ position: MackieClockPosition) {
        referenceBar = position.bar
    }
}
