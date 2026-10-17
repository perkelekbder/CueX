import Foundation

enum MackieFeedbackEvent: Sendable {
    case note(number: UInt8, value: UInt8)
    case display(index: Int, value: UInt8)
}

enum MackieClockMode: Sendable {
    case unknown, beats, smpte
}

struct MackieClockPosition: Equatable, Sendable {
    let bar: Int
    let beat: Int
    let division: Int
    let tick: Int

    var label: String { "Bar \(bar) · Beat \(beat)" }
}

/// Logic sends the ten clock digits right to left using CC 0x40...0x49.
/// It only resends changed digits, so retain the rest until the next update.
struct MackiePositionDecoder {
    private var digits: [UInt8?] = Array(repeating: nil, count: 10)
    private(set) var mode: MackieClockMode = .unknown

    mutating func consume(_ event: MackieFeedbackEvent) {
        switch event {
        case let .display(index, value):
            guard (0..<10).contains(index) else { return }
            digits[9 - index] = value & 0x3F // bit 6 is the decimal-point LED
        case let .note(number, value) where value > 0:
            if number == 0x72 { mode = .beats }
            if number == 0x71 { mode = .smpte }
        default:
            break
        }
    }

    // Bar 000 is valid on the display at absolute bars 1000, 2000, etc.
    // LogicMIDIController resolves these raw digits using the last cue/position.
    var position: MackieClockPosition? {
        guard mode == .beats,
              let bar = number(in: 0..<3), bar >= 0,
              let beat = number(in: 3..<5), beat > 0,
              let division = number(in: 5..<7), division > 0,
              let tick = number(in: 7..<10), tick > 0 else { return nil }
        return MackieClockPosition(bar: bar, beat: beat, division: division, tick: tick)
    }

    private func number(in range: Range<Int>) -> Int? {
        let bytes = digits[range].compactMap { $0 }
        guard bytes.count == range.count,
              bytes.allSatisfy({ $0 == 0x20 || (0x30...0x39).contains($0) }) else { return nil }
        return Int(String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces))
    }
}
