import SwiftUI

struct BatteryPowerWarning: View {
    let monitor: BatteryPowerMonitor

    private var warningColor: Color { monitor.isLow ? LogicTheme.red : .yellow }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(warningColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.isLow ? "Low battery" : "Running on battery")
                    .font(.system(size: 17, weight: .medium))
                Text(monitor.chargePercent.map { "\($0)% remaining · Connect power" } ?? "Connect power to your Mac")
                    .font(.caption)
                    .foregroundStyle(LogicTheme.secondaryText)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .padding(.vertical, 3)
        .background(warningColor.opacity(0.1))
        .background(LogicTheme.panel)
        .accessibilityElement(children: .combine)
        .help("Battery warning: yellow while running on battery, red at 20% or below. Hidden when connected to external power.")
    }
}
