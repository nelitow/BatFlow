import Foundation
import IOKit

public struct PortInfo: Identifiable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let watts: Double
    public let voltageVolts: Double
    public let currentAmps: Double
    public let configuredVoltageVolts: Double
    public let configuredCurrentAmps: Double
    public let isConnected: Bool
}

public struct PowerSnapshot: Sendable {
    public let timestamp: Date
    public let batteryPercent: Int
    public let batteryTempC: Double
    public let isCharging: Bool
    public let isFullyCharged: Bool
    public let hasChargerConnected: Bool
    public let chargerName: String
    public let chargerWattsNominal: Double
    public let chargerWattsActual: Double
    public let batteryWatts: Double
    public let systemWatts: Double
    public let outputPortsWatts: Double
    public let ports: [PortInfo]
    public let voltageVolts: Double
    public let amperageAmps: Double
    public let healthPercent: Double
    public let cycleCount: Int
    public let timeToEmptyMin: Int?
    public let timeToFullMin: Int?
}

// MARK: - SMC Interop Structs & Constants

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

public final class PowerTelemetryService: @unchecked Sendable {
    public static let shared = PowerTelemetryService()
    
    private init() {}
    
    private func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for char in string.utf8 {
            result = (result << 8) | UInt32(char)
        }
        return result
    }
    
    // Read float key from AppleSMC
    private func readSMCFloatKey(_ keyStr: String) -> Double? {
        let matching = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return nil }
        defer { IOServiceClose(conn) }
        
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        
        var inputStructure = SMCParamStruct()
        var outputStructure = SMCParamStruct()
        inputStructure.key = fourCharCode(keyStr)
        inputStructure.data8 = 9 // kSMCGetKeyInfo
        
        guard IOConnectCallStructMethod(conn, 2, &inputStructure, inputSize, &outputStructure, &outputSize) == kIOReturnSuccess,
              outputStructure.keyInfo.dataSize == 4 else {
            return nil
        }
        
        inputStructure.keyInfo.dataSize = 4
        inputStructure.data8 = 5 // kSMCReadKey
        
        guard IOConnectCallStructMethod(conn, 2, &inputStructure, inputSize, &outputStructure, &outputSize) == kIOReturnSuccess else {
            return nil
        }
        
        let b = outputStructure.bytes
        let rawBytes = [b.0, b.1, b.2, b.3]
        let floatVal = rawBytes.withUnsafeBytes { $0.load(as: Float.self) }
        
        guard !floatVal.isNaN && !floatVal.isInfinite && floatVal > -50 && floatVal < 200 else {
            return nil
        }
        return Double(floatVal)
    }
    
    public func fetchSnapshot() -> PowerSnapshot {
        var batteryPercent: Int = 0
        var isCharging: Bool = false
        var isFullyCharged: Bool = false
        var hasChargerConnected: Bool = false
        var chargerName: String = "Disconnected"
        var chargerWattsNominal: Double = 0.0
        var chargerWattsActual: Double = 0.0
        var batteryWatts: Double = 0.0
        var rawVoltage: Double = 0.0 // mV
        var amperage: Double = 0.0 // mA
        var healthPercent: Double = 100.0
        var cycleCount: Int = 0
        var timeToEmptyMin: Int? = nil
        var timeToFullMin: Int? = nil
        var ports: [PortInfo] = []
        var totalOutputWatts: Double = 0.0
        
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                
                // Capacity & Percent
                if let batteryData = dict["BatteryData"] as? [String: Any] {
                    let curCap = (batteryData["CurrentCapacity"] as? NSNumber)?.doubleValue ?? 0
                    let maxCap = (batteryData["MaxCapacity"] as? NSNumber)?.doubleValue ?? 100
                    let designCap = (batteryData["DesignCapacity"] as? NSNumber)?.doubleValue ?? 8500
                    let fullCap = (batteryData["FullChargeCapacity"] as? NSNumber)?.doubleValue ?? 8000
                    
                    batteryPercent = Int(curCap)
                    if maxCap > 0 && maxCap <= 100 {
                        batteryPercent = Int(curCap)
                    }
                    if designCap > 0 {
                        healthPercent = min(100.0, (fullCap / designCap) * 100.0)
                    }
                    
                    if let batPwr = batteryData["BatteryPower"] as? NSNumber {
                        // mW
                        let pwrW = batPwr.doubleValue / 1000.0
                        batteryWatts = pwrW
                    }
                } else if let curCap = dict["CurrentCapacity"] as? NSNumber,
                          let maxCap = dict["MaxCapacity"] as? NSNumber {
                    batteryPercent = Int((curCap.doubleValue / maxCap.doubleValue) * 100)
                }
                
                // Status flags
                if let charging = dict["IsCharging"] as? Bool { isCharging = charging }
                else if let chargingNum = dict["IsCharging"] as? NSNumber { isCharging = chargingNum.boolValue }
                
                if let fully = dict["FullyCharged"] as? Bool { isFullyCharged = fully }
                else if let fullyNum = dict["FullyCharged"] as? NSNumber { isFullyCharged = fullyNum.boolValue }
                
                if let extConn = dict["ExternalConnected"] as? Bool { hasChargerConnected = extConn }
                else if let extConnNum = dict["ExternalConnected"] as? NSNumber { hasChargerConnected = extConnNum.boolValue }
                
                // Voltage & Amperage
                if let v = dict["AppleRawBatteryVoltage"] as? NSNumber { rawVoltage = v.doubleValue }
                else if let v = dict["Voltage"] as? NSNumber { rawVoltage = v.doubleValue }
                
                if let a = dict["InstantAmperage"] as? NSNumber { amperage = a.doubleValue }
                else if let a = dict["Amperage"] as? NSNumber { amperage = a.doubleValue }
                
                // Battery Watts calculation refinement
                let calculatedWatts = (rawVoltage * amperage) / 1_000_000.0
                if abs(calculatedWatts) > 0.05 {
                    batteryWatts = calculatedWatts
                }
                
                // Cycles
                if let cycles = dict["CycleCount"] as? NSNumber { cycleCount = cycles.intValue }
                
                // Times
                if let tEmpty = dict["AvgTimeToEmpty"] as? NSNumber, tEmpty.intValue > 0 && tEmpty.intValue < 65000 {
                    timeToEmptyMin = tEmpty.intValue
                }
                if let tFull = dict["AvgTimeToFull"] as? NSNumber, tFull.intValue > 0 && tFull.intValue < 65000 {
                    timeToFullMin = tFull.intValue
                }
                
                // Charger Details
                if let adapter = dict["AdapterDetails"] as? [String: Any] {
                    chargerName = (adapter["Name"] as? String) ?? "USB-C Power Adapter"
                    chargerWattsNominal = (adapter["Watts"] as? NSNumber)?.doubleValue ?? 0.0
                    let aVoltage = (adapter["AdapterVoltage"] as? NSNumber)?.doubleValue ?? 0.0 // mV
                    let aCurrent = (adapter["Current"] as? NSNumber)?.doubleValue ?? 0.0 // mA
                    if aVoltage > 0 && aCurrent > 0 {
                        chargerWattsActual = (aVoltage * aCurrent) / 1_000_000.0
                    } else {
                        chargerWattsActual = chargerWattsNominal
                    }
                }
                
                // Output Ports Details
                if let powerOutArray = dict["PowerOutDetails"] as? [[String: Any]] {
                    for (idx, pDict) in powerOutArray.enumerated() {
                        let wattsmW = (pDict["Watts"] as? NSNumber)?.doubleValue ?? (pDict["FilteredPower"] as? NSNumber)?.doubleValue ?? 0.0
                        let portWatts = wattsmW / 1000.0
                        let v = ((pDict["AdapterVoltage"] as? NSNumber)?.doubleValue ?? 0.0) / 1000.0
                        let c = ((pDict["Current"] as? NSNumber)?.doubleValue ?? 0.0) / 1000.0
                        let cfgV = ((pDict["ConfiguredVoltage"] as? NSNumber)?.doubleValue ?? 0.0) / 1000.0
                        let cfgC = ((pDict["ConfiguredCurrent"] as? NSNumber)?.doubleValue ?? 0.0) / 1000.0
                        let isConn = portWatts > 0.05 || c > 0.05
                        
                        ports.append(PortInfo(
                            index: idx + 1,
                            watts: max(0.0, portWatts),
                            voltageVolts: max(0.0, v),
                            currentAmps: max(0.0, c),
                            configuredVoltageVolts: max(0.0, cfgV),
                            configuredCurrentAmps: max(0.0, cfgC),
                            isConnected: isConn
                        ))
                        
                        if isConn {
                            totalOutputWatts += max(0.0, portWatts)
                        }
                    }
                }
            }
            IOObjectRelease(service)
        }
        
        // Battery Temp from SMC (TB0T, TB1T, TB2T)
        var batteryTempC: Double = 30.0
        let tempKeys = ["TB0T", "TB1T", "TB2T"]
        var validTemps: [Double] = []
        for key in tempKeys {
            if let t = readSMCFloatKey(key), t > 5.0 && t < 90.0 {
                validTemps.append(t)
            }
        }
        if !validTemps.isEmpty {
            batteryTempC = validTemps.reduce(0, +) / Double(validTemps.count)
        }
        
        // System Watts (Mac usage / CPU / board)
        var systemWatts: Double = 0.0
        if let smcSysPower = readSMCFloatKey("PSTR"), smcSysPower > 0.1 && smcSysPower < 300.0 {
            systemWatts = smcSysPower
        } else {
            // Fallback physics model:
            if hasChargerConnected {
                let batChargeWatts = max(0.0, batteryWatts)
                systemWatts = max(3.5, chargerWattsActual - batChargeWatts - totalOutputWatts)
            } else {
                let batDischargeWatts = max(0.0, -batteryWatts)
                systemWatts = max(3.5, batDischargeWatts - totalOutputWatts)
            }
        }
        
        return PowerSnapshot(
            timestamp: Date(),
            batteryPercent: batteryPercent,
            batteryTempC: batteryTempC,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            hasChargerConnected: hasChargerConnected,
            chargerName: chargerName,
            chargerWattsNominal: chargerWattsNominal,
            chargerWattsActual: chargerWattsActual,
            batteryWatts: batteryWatts,
            systemWatts: systemWatts,
            outputPortsWatts: totalOutputWatts,
            ports: ports,
            voltageVolts: rawVoltage / 1000.0,
            amperageAmps: amperage / 1000.0,
            healthPercent: healthPercent,
            cycleCount: cycleCount,
            timeToEmptyMin: timeToEmptyMin,
            timeToFullMin: timeToFullMin
        )
    }
}
