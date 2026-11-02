import SwiftUI
import Charts

struct PowerCard: View {
    @ObservedObject var viewModel: TelemetryViewModel

    var body: some View {
        let snap = viewModel.currentSnapshot

        NotchCard(title: "Power", systemImage: "bolt.fill", tint: .green) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(snap.batteryPercent)%")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Image(systemName: BatteryGlyph.name(percent: snap.batteryPercent, charging: snap.isCharging || snap.hasChargerConnected))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(snap.isCharging ? Color.green : Color.white, Color.white.opacity(0.35))
                            .font(.system(size: 20))
                    }
                    Text(statusLine(snap))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                VStack(spacing: 7) {
                    MetricRow(
                        icon: "powerplug.fill",
                        label: "Adapter",
                        value: snap.hasChargerConnected ? watts(snap.chargerWattsActual) : "—",
                        tint: .green
                    )
                    MetricRow(icon: "cpu", label: "System", value: watts(snap.systemWatts), tint: .blue)
                    MetricRow(
                        icon: "battery.100percent",
                        label: "Battery",
                        value: String(format: "%@%.1f W", snap.batteryWatts > 0.05 ? "+" : "", snap.batteryWatts),
                        tint: snap.batteryWatts < -0.05 ? .orange : .green
                    )
                    MetricRow(icon: "cable.connector", label: "Accessories", value: watts(snap.outputPortsWatts), tint: .purple)
                    MetricRow(icon: "thermometer.medium", label: "Temperature", value: viewModel.formattedTemp(snap.batteryTempC), tint: .orange)
                }

                Spacer(minLength: 0)

                SystemPowerSparkline(history: viewModel.history)
                    .frame(height: 40)
            }
        }
    }

    private func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    private func statusLine(_ snap: PowerSnapshot) -> String {
        if snap.isFullyCharged { return "Fully charged" }
        if let minutes = snap.timeToFullMin { return "Charging · \(duration(minutes)) until full" }
        if snap.isCharging { return "Charging" }
        if snap.hasChargerConnected { return "Not charging · On power adapter" }
        if let minutes = snap.timeToEmptyMin { return "\(duration(minutes)) remaining" }
        return "On battery"
    }

    private func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) hr \(m) min" : "\(m) min"
    }
}

private struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
        }
    }
}

private struct SystemPowerSparkline: View {
    let history: [PowerSnapshot]

    var body: some View {
        if history.count < 2 {
            Text("Collecting samples…")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(Array(history.enumerated()), id: \.offset) { index, item in
                    AreaMark(x: .value("Sample", index), y: .value("System", item.systemWatts))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0)], startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Sample", index), y: .value("System", item.systemWatts))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
        }
    }
}
