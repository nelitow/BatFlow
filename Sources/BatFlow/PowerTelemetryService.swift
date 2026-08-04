import Foundation
import IOKit

struct PowerSnapshot {
    let batteryPercent: Int
    let isCharging: Bool
    let isFullyCharged: Bool
    let cycleCount: Int
    let voltageVolts: Double
    let amperageAmps: Double
    let designCapacity: Int
    let maxCapacity: Int
    let healthPercent: Double
}

enum PowerTelemetryService {
    static func fetchSnapshot() -> PowerSnapshot? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var cfProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &cfProperties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let properties = cfProperties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let percent = properties["CurrentCapacity"] as? Int ?? 0
        let isCharging = properties["IsCharging"] as? Bool ?? false
        let isFullyCharged = properties["FullyCharged"] as? Bool ?? false
        let cycleCount = properties["CycleCount"] as? Int ?? 0
        let voltageMillivolts = properties["Voltage"] as? Int ?? 0
        let amperageMilliamps = properties["Amperage"] as? Int ?? 0
        let designCapacity = properties["DesignCapacity"] as? Int ?? 0
        let maxCapacity = (properties["AppleRawMaxCapacity"] as? Int) ?? (properties["MaxCapacity"] as? Int) ?? 0

        let healthPercent = designCapacity > 0 ? (Double(maxCapacity) / Double(designCapacity)) * 100.0 : 0

        return PowerSnapshot(
            batteryPercent: percent,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            cycleCount: cycleCount,
            voltageVolts: Double(voltageMillivolts) / 1000.0,
            amperageAmps: Double(amperageMilliamps) / 1000.0,
            designCapacity: designCapacity,
            maxCapacity: maxCapacity,
            healthPercent: healthPercent
        )
    }
}
