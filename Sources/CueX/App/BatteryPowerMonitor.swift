import Foundation
import IOKit.ps
import Observation

private extension Notification.Name {
    static let cueXPowerSourceChanged = Notification.Name("CueXPowerSourceChanged")
}

@Observable
@MainActor
final class BatteryPowerMonitor {
    private(set) var isOnBattery = false
    private(set) var chargePercent: Int?
    var isLow: Bool { chargePercent.map { $0 <= 20 } ?? false }
    @ObservationIgnored private var observation: PowerSourceObservation?

    init() {
        observation = PowerSourceObservation { [weak self] in self?.refresh() }
        refresh()
    }

    private func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            isOnBattery = false
            chargePercent = nil
            return
        }
        var percentages: [Int] = []
        var onBattery = false
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool != false else { continue }
            // AC-powered batteries include charging, full, and charging-paused states.
            guard description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue else { continue }
            onBattery = true
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0, current >= 0 {
                let percent = Int((Double(current) / Double(maximum) * 100).rounded(.down))
                percentages.append(min(100, max(0, percent)))
            }
        }
        isOnBattery = onBattery
        chargePercent = percentages.min()
    }
}

/// Owns and removes the native power-change subscription, without retaining the monitor.
private final class PowerSourceObservation {
    private let source: CFRunLoopSource
    private let observer: NSObjectProtocol

    @MainActor
    init?(onChange: @escaping @MainActor () -> Void) {
        guard let source = IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(name: .cueXPowerSourceChanged, object: nil)
        }, nil)?.takeRetainedValue() else { return nil }
        self.source = source
        observer = NotificationCenter.default.addObserver(
            forName: .cueXPowerSourceChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange() }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    deinit {
        CFRunLoopSourceInvalidate(source)
        NotificationCenter.default.removeObserver(observer)
    }
}
