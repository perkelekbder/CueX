import Foundation

/// Logic doesn't identify the source of a locate in its MCU feedback. A jump
/// to its exact project start is treated as Return to Start only while stopped.
/// Cues explicitly sent by CueX to tick zero remain valid.
struct ProjectStartReturnGuard {
    private var lastPosition: MackieClockPosition?
    private var lastSample: ContinuousClock.Instant?
    private var intentionalProjectStart = false
    private var locateSentAt: ContinuousClock.Instant?
    private var returnPending = false

    mutating func reset(position: MackieClockPosition?, receivedAt: ContinuousClock.Instant?) {
        self = Self()
        lastPosition = position
        lastSample = receivedAt
    }

    mutating func didLocate(tick: Int, sentAt: ContinuousClock.Instant) {
        intentionalProjectStart = tick == 0
        locateSentAt = sentAt
        returnPending = false
    }

    mutating func observe(position: MackieClockPosition?, receivedAt: ContinuousClock.Instant?, isPlaying: Bool?) -> Bool {
        if let position, let receivedAt,
           lastSample.map({ receivedAt > $0 }) ?? true,
           locateSentAt.map({ receivedAt > $0 }) ?? true {
            let atStart = Self.isProjectStart(position)
            if !atStart {
                returnPending = false
                intentionalProjectStart = false
            } else if let lastPosition, !Self.isProjectStart(lastPosition), !intentionalProjectStart {
                // Keep this pending if the position arrives before stopped feedback.
                returnPending = true
            }
            lastPosition = position
            lastSample = receivedAt
        }
        guard isPlaying == false, returnPending else { return false }
        returnPending = false
        return true
    }

    private static func isProjectStart(_ position: MackieClockPosition) -> Bool {
        position.bar == 1 && position.beat == 1 && position.division == 1 && position.tick == 1
    }
}
