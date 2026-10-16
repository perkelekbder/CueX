import Foundation

struct TimeSignature: Hashable, Codable, Identifiable {
    var startTick: Int
    var numerator: Int
    var denominator: Int

    var id: Int { startTick }
    var beatTicks: Int { 3_840 / denominator }
    var barTicks: Int { numerator * beatTicks }
    var label: String { "\(numerator)/\(denominator)" }
}

struct MusicalPosition {
    let bar: Int
    let beat: Int
    let beatRemainderTicks: Int
}
