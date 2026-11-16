import AppKit
import Darwin

/// One app's estimated share of system power.
struct AppPowerEstimate: Identifiable {
    let id: String // bundle path
    let name: String
    let icon: NSImage
    let watts: Double
}

/// Estimates power per app by splitting the measured system draw by CPU time.
///
/// macOS exposes no per-app wattage, so this is a guess: each process's CPU time
/// since the last sample is credited to its enclosing `.app` (helpers included),
/// and the system draw above its recent idle floor is shared out by those weights.
/// Processes owned by other users (WindowServer, kernel_task) can't be read and
/// fall into the remainder along with the display and the idle floor.
@MainActor
final class AppPowerSampler {
    private struct AppInfo {
        let name: String
        let icon: NSImage
    }

    private var lastCPU: [pid_t: UInt64] = [:]
    private var hasBaseline = false
    /// pid -> enclosing app path, or nil for processes outside any `.app`.
    private var pidBundle: [pid_t: String?] = [:]
    private var appInfo: [String: AppInfo] = [:]
    private let ownBundlePath = Bundle.main.bundlePath

    func reset() {
        lastCPU = [:]
        hasBaseline = false
        pidBundle = [:]
    }

    /// Returns `nil` on the first call after a reset, when there is no interval yet.
    func sample(activeWatts: Double) -> [AppPowerEstimate]? {
        var cpuNow: [pid_t: UInt64] = [:]
        var cpuByApp: [String: Double] = [:]
        var totalCPU: Double = 0

        for pid in Self.allPIDs() {
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard result == 0 else { continue }
            let cpu = info.ri_user_time &+ info.ri_system_time
            cpuNow[pid] = cpu

            guard let previous = lastCPU[pid], cpu >= previous else { continue }
            let delta = Double(cpu - previous)
            guard delta > 0 else { continue }
            totalCPU += delta
            if let bundle = bundlePath(for: pid) {
                cpuByApp[bundle, default: 0] += delta
            }
        }

        let hadBaseline = hasBaseline
        lastCPU = cpuNow
        hasBaseline = true
        pidBundle = pidBundle.filter { cpuNow[$0.key] != nil }
        guard hadBaseline else { return nil }
        guard totalCPU > 0 else { return [] }

        return cpuByApp.compactMap { path, cpu in
            let watts = activeWatts * cpu / totalCPU
            guard watts >= 0.05, let info = info(forApp: path) else { return nil }
            return AppPowerEstimate(id: path, name: info.name, icon: info.icon, watts: watts)
        }
        .sorted { $0.watts > $1.watts }
    }

    private static func allPIDs() -> [pid_t] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(max(0, Int(count))))
    }

    /// The outermost `.app` containing the process's executable, so Chrome's
    /// helpers (nested `.app`s inside Google Chrome.app) count as Chrome.
    private func bundlePath(for pid: pid_t) -> String? {
        if let cached = pidBundle[pid] { return cached }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        var bundle: String?
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = String(cString: buffer)
            if let range = path.range(of: ".app/") {
                let candidate = String(path[..<range.lowerBound]) + ".app"
                bundle = candidate == ownBundlePath ? nil : candidate
            }
        }
        pidBundle[pid] = bundle
        return bundle
    }

    private func info(forApp path: String) -> AppInfo? {
        if let cached = appInfo[path] { return cached }
        let url = URL(fileURLWithPath: path)
        let bundle = Bundle(url: url)
        let name = (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let info = AppInfo(name: name, icon: NSWorkspace.shared.icon(forFile: path))
        appInfo[path] = info
        return info
    }
}
