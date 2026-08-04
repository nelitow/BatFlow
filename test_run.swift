import Foundation
import IOKit

@main
struct TestRunner {
    static func main() {
        let snapshot = PowerTelemetryService.shared.fetchSnapshot()

        print("========== BATFLOW HARDWARE TELEMETRY SNAPSHOT ==========")
        print("Timestamp            :", snapshot.timestamp)
        print("Battery Level        :", "\(snapshot.batteryPercent)%")
        print("Battery Temperature  :", String(format: "%.1f°C / %.1f°F", snapshot.batteryTempC, (snapshot.batteryTempC * 9.0/5.0) + 32.0))
        print("Charging Status      :", snapshot.isCharging ? "Charging" : (snapshot.isFullyCharged ? "Fully Charged" : "Discharging"))
        print("Charger Connected    :", snapshot.hasChargerConnected ? "YES" : "NO")
        print("Charger Name         :", snapshot.chargerName)
        print("Charger Nominal Watts:", String(format: "%.1f W", snapshot.chargerWattsNominal))
        print("Charger Actual Watts :", String(format: "%.1f W", snapshot.chargerWattsActual))
        print("Battery Flow Watts   :", String(format: "%.2f W", snapshot.batteryWatts))
        print("Mac Usage (CPU/Sys)  :", String(format: "%.2f W", snapshot.systemWatts))
        print("USB-C Output Watts   :", String(format: "%.2f W", snapshot.outputPortsWatts))
        print("Battery Health       :", String(format: "%.1f%%", snapshot.healthPercent))
        print("Cycle Count          :", snapshot.cycleCount)
        print("Voltage              :", String(format: "%.2f V", snapshot.voltageVolts))
        print("Amperage             :", String(format: "%.2f A", snapshot.amperageAmps))

        print("\n--- USB-C Ports Breakdown (\(snapshot.ports.count) ports) ---")
        for p in snapshot.ports {
            print("Port \(p.index): \(p.isConnected ? "CONNECTED" : "Idle") | \(String(format: "%.2f W", p.watts)) | \(String(format: "%.2f V", p.voltageVolts)) | \(String(format: "%.2f A", p.currentAmps))")
        }
        print("=========================================================")
    }
}
