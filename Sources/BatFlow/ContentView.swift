import SwiftUI

struct ContentView: View {
    @State private var snapshot: PowerSnapshot?
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BatFlow").font(.headline)

            if let snapshot {
                Label("\(snapshot.batteryPercent)%", systemImage: "battery.100")
                Text(statusText(for: snapshot))
                    .foregroundStyle(.secondary)
                Divider()
                telemetryRow("Cycle Count", "\(snapshot.cycleCount)")
                telemetryRow("Health", String(format: "%.0f%%", snapshot.healthPercent))
                telemetryRow("Voltage", String(format: "%.2f V", snapshot.voltageVolts))
                telemetryRow("Amperage", String(format: "%.2f A", snapshot.amperageAmps))
            } else {
                Text("Reading battery telemetry…")
                    .foregroundStyle(.secondary)
            }

            Divider()
            Button("Quit BatFlow") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 220)
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func statusText(for snapshot: PowerSnapshot) -> String {
        if snapshot.isCharging { return "Charging" }
        if snapshot.isFullyCharged { return "Fully Charged" }
        return "On Battery"
    }

    private func refresh() {
        snapshot = PowerTelemetryService.fetchSnapshot()
    }

    private func telemetryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.system(.body, design: .monospaced))
    }
}
