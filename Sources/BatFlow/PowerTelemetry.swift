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
    /// Rated output of the adapter, e.g. 140 W for a 140 W brick. Constant.
    public let chargerWattsNominal: Double
    /// Ceiling of the negotiated USB-PD contract (contract voltage × contract current),
    /// e.g. 28 V × 4.99 A = 139.7 W. This is a *limit*, not a measurement: it stays flat
    /// while the charger is attached. Never display it as consumption.
    public let chargerWattsNegotiated: Double
    /// Power the adapter is actually delivering right now (SMC `PDTR`).
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
    /// Method selectors understood by AppleSMC's `IOConnectCallStructMethod` handler.
    enum Selector: UInt8 {
        case readKey = 5
        case getKeyInfo = 9
    }

    /// Values AppleSMC reports back in `result`. A non-zero `result` accompanies a
    /// `kIOReturnSuccess` ioctl, so the ioctl return code alone says nothing about
    /// whether the key was actually read.
    enum Result: UInt8 {
        case success = 0
        case keyNotFound = 132
    }

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

/// FourCharCode for the SMC `flt ` (32-bit IEEE float) data type.
private let smcFloatType: UInt32 = 0x666C_7420 // "flt "

public final class PowerTelemetryService: @unchecked Sendable {
    public static let shared = PowerTelemetryService()
    
    private init() {}
    
    // MARK: - SMC access

    /// AppleSMC connection, opened lazily and kept for the life of the process.
    /// `fetchSnapshot` reads several keys per poll; reopening the driver for each one
    /// costs two Mach round trips per key for no benefit.
    private var smcConnection: io_connect_t = 0
    private var smcOpenFailed = false
    private let smcLock = NSLock()

    private func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for char in string.utf8 {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    /// Caller must hold `smcLock`.
    private func smcConnect() -> io_connect_t? {
        if smcConnection != 0 { return smcConnection }
        if smcOpenFailed { return nil }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            smcOpenFailed = true
            return nil
        }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            smcOpenFailed = true
            return nil
        }
        smcConnection = conn
        return conn
    }

    /// Caller must hold `smcLock`. Returns the populated output struct, or `nil` when
    /// either the ioctl or the SMC itself reported failure.
    private func smcCall(_ input: inout SMCParamStruct, on conn: io_connect_t) -> SMCParamStruct? {
        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        guard IOConnectCallStructMethod(conn, 2, &input, inputSize, &output, &outputSize) == kIOReturnSuccess,
              output.result == SMCParamStruct.Result.success.rawValue else {
            // A missing key returns kIOReturnSuccess with result == 132; without this
            // check the untouched output buffer would be decoded as a valid 0.0 reading.
            return nil
        }
        return output
    }

    /// Reads a 32-bit float SMC key. Returns `nil` if the key is absent on this Mac,
    /// is not a `flt ` key, or the read fails.
    private func readSMCFloatKey(_ keyStr: String) -> Double? {
        smcLock.lock()
        defer { smcLock.unlock() }

        guard let conn = smcConnect() else { return nil }
        let key = fourCharCode(keyStr)

        var infoInput = SMCParamStruct()
        infoInput.key = key
        infoInput.data8 = SMCParamStruct.Selector.getKeyInfo.rawValue
        guard let info = smcCall(&infoInput, on: conn),
              info.keyInfo.dataType == smcFloatType,
              info.keyInfo.dataSize == 4 else {
            return nil
        }

        var readInput = SMCParamStruct()
        readInput.key = key
        readInput.keyInfo.dataSize = 4
        readInput.data8 = SMCParamStruct.Selector.readKey.rawValue
        guard let output = smcCall(&readInput, on: conn) else { return nil }

        // The SMC returns `flt ` little-endian. Assemble the bit pattern explicitly:
        // binding a [UInt8] buffer and calling `load(as: Float.self)` on it is undefined
        // behaviour (the memory is bound to UInt8, not Float) and the optimiser miscompiles
        // it to a constant 0.0 in release builds.
        let b = output.bytes
        let bits = UInt32(b.0) | UInt32(b.1) << 8 | UInt32(b.2) << 16 | UInt32(b.3) << 24
        let value = Float(bitPattern: bits)

        guard value.isFinite else { return nil }
        return Double(value)
    }
    
    public func fetchSnapshot() -> PowerSnapshot {
        var batteryPercent: Int = 0
        var isCharging: Bool = false
        var isFullyCharged: Bool = false
        var hasChargerConnected: Bool = false
        var chargerName: String = "Disconnected"
        var chargerWattsNominal: Double = 0.0
        var chargerWattsNegotiated: Double = 0.0
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
                
                // Charger Details.
                // `AdapterVoltage` and `Current` describe the negotiated USB-PD contract
                // (e.g. 28 V @ 4.99 A on a 140 W brick), i.e. the ceiling the adapter has
                // agreed to supply. They do not move with load, so they must never be
                // reported as draw — the measured delivery comes from SMC `PDTR` below.
                if let adapter = dict["AdapterDetails"] as? [String: Any] {
                    chargerName = (adapter["Name"] as? String) ?? "USB-C Power Adapter"
                    chargerWattsNominal = (adapter["Watts"] as? NSNumber)?.doubleValue ?? 0.0
                    let contractVoltage = (adapter["AdapterVoltage"] as? NSNumber)?.doubleValue ?? 0.0 // mV
                    let contractCurrent = (adapter["Current"] as? NSNumber)?.doubleValue ?? 0.0 // mA
                    if contractVoltage > 0 && contractCurrent > 0 {
                        chargerWattsNegotiated = (contractVoltage * contractCurrent) / 1_000_000.0
                    } else {
                        chargerWattsNegotiated = chargerWattsNominal
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
        
        // Measured power rails, following BatFi's model: `PDTR` is what the adapter is
        // actually delivering and `PSTR` is what the system itself is drawing. Both track
        // load in real time; the USB-PD contract figures above do not.
        func measuredWatts(_ key: String) -> Double? {
            guard let w = readSMCFloatKey(key), w >= -400.0, w <= 400.0 else { return nil }
            return w
        }
        let measuredAdapterWatts = hasChargerConnected ? measuredWatts("PDTR") : nil
        let measuredSystemWatts = measuredWatts("PSTR")

        // System Watts (Mac usage / CPU / board)
        let systemWatts: Double
        if let measured = measuredSystemWatts {
            systemWatts = max(0.0, measured)
        } else if hasChargerConnected, let adapter = measuredAdapterWatts {
            // Whatever the adapter supplies that is not going into the pack or out a port.
            systemWatts = max(0.0, adapter - max(0.0, batteryWatts) - totalOutputWatts)
        } else {
            // Running on the pack: it is the only source feeding the board and the ports.
            systemWatts = max(0.0, -batteryWatts - totalOutputWatts)
        }

        // What the charger is really supplying right now.
        let chargerWattsActual: Double
        if !hasChargerConnected {
            chargerWattsActual = 0.0
        } else if let measured = measuredAdapterWatts {
            chargerWattsActual = measured
        } else {
            // No PDTR on this Mac: reconstruct from the loads the adapter is feeding.
            chargerWattsActual = max(0.0, systemWatts + max(0.0, batteryWatts) + totalOutputWatts)
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
            chargerWattsNegotiated: chargerWattsNegotiated,
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
