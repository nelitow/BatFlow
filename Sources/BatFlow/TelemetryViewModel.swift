import Foundation
import Combine
import SwiftUI

public enum TempUnit: String, CaseIterable, Identifiable, Codable {
    case celsius = "°C"
    case fahrenheit = "°F"
    
    public var id: String { rawValue }
}

public enum StatusBarFormat: String, CaseIterable, Identifiable, Codable {
    case compact = "⚡️ 28% • 31°C"
    case full = "⚡️ 28% • 31°C • 20W"
    case percentOnly = "⚡️ 28%"
    case wattsOnly = "⚡️ 20W"
    
    public var id: String { rawValue }
}

extension Notification.Name {
    static let batFlowHotKeySettingChanged = Notification.Name("BatFlowHotKeySettingChanged")
}

@MainActor
public final class TelemetryViewModel: ObservableObject {
    @Published public private(set) var currentSnapshot: PowerSnapshot
    @Published public private(set) var history: [PowerSnapshot] = []
    /// Separate from `currentSnapshot` so the status-item sink ignores heavy poll churn.
    @Published public private(set) var menuBarTitle: String = ""
    
    /// True while the popover UI is on screen. When no UI surface is visible we still
    /// poll for the menu bar, but skip history accumulation and snapshot publishing.
    public var isPopoverVisible: Bool = false {
        didSet { if isPopoverVisible { seedVisibleUI() } }
    }
    
    /// True while the notch panel is open. Tracked separately from the popover because
    /// both can be on screen at once.
    public var isNotchVisible: Bool = false {
        didSet { if isNotchVisible { seedVisibleUI() } }
    }
    
    private var isAnyUIVisible: Bool { isPopoverVisible || isNotchVisible }
    
    private func seedVisibleUI() {
        // Seed the UI with the freshest bar-only sample on open.
        currentSnapshot = latestSnapshot
        if history.last?.timestamp != latestSnapshot.timestamp {
            history.append(latestSnapshot)
            if history.count > 180 {
                history.removeFirst(history.count - 180)
            }
        }
    }
    
    @AppStorage("tempUnit") public var tempUnit: TempUnit = .celsius {
        didSet { publishMenuBarTitle() }
    }
    @AppStorage("pollingInterval") public var pollingInterval: Double = 2.0 {
        didSet { restartTimer() }
    }
    @AppStorage("statusBarFormat") public var statusBarFormat: StatusBarFormat = .full {
        didSet { publishMenuBarTitle() }
    }
    @AppStorage("showHealthAndCycles") public var showHealthAndCycles: Bool = false
    @AppStorage("notchOpensOnHover") public var notchOpensOnHover: Bool = true
    @AppStorage("notchHotKeyEnabled") public var notchHotKeyEnabled: Bool = true {
        didSet { NotificationCenter.default.post(name: .batFlowHotKeySettingChanged, object: nil) }
    }
    
    private var timerCancellable: AnyCancellable?
    private let service = PowerTelemetryService.shared
    /// Latest poll retained without publishing while the popover is closed.
    private var latestSnapshot: PowerSnapshot
    
    public init() {
        let initial = service.fetchSnapshot()
        self.currentSnapshot = initial
        self.latestSnapshot = initial
        self.history.append(initial)
        self.menuBarTitle = Self.makeMenuBarTitle(snapshot: initial, tempUnit: tempUnit, format: statusBarFormat)
        startTimer()
    }
    
    public func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: pollingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }
    
    public func restartTimer() {
        startTimer()
    }
    
    public func refresh() {
        let snap = service.fetchSnapshot()
        latestSnapshot = snap
        let title = Self.makeMenuBarTitle(snapshot: snap, tempUnit: tempUnit, format: statusBarFormat)
        
        if title != menuBarTitle {
            menuBarTitle = title
        }
        
        // Menu-bar-only: do not publish snapshot/history (nothing visible needs them).
        guard isAnyUIVisible else { return }
        
        currentSnapshot = snap
        history.append(snap)
        
        // Retain max 180 snapshots (approx 6 minutes at 2s interval)
        if history.count > 180 {
            history.removeFirst(history.count - 180)
        }
    }
    
    public func formattedTemp(_ tempC: Double) -> String {
        Self.formatTemp(tempC, unit: tempUnit)
    }
    
    private func publishMenuBarTitle() {
        menuBarTitle = Self.makeMenuBarTitle(
            snapshot: latestSnapshot,
            tempUnit: tempUnit,
            format: statusBarFormat
        )
    }
    
    private static func formatTemp(_ tempC: Double, unit: TempUnit) -> String {
        switch unit {
        case .celsius:
            return String(format: "%.1f°C", tempC)
        case .fahrenheit:
            let f = (tempC * 9.0 / 5.0) + 32.0
            return String(format: "%.1f°F", f)
        }
    }
    
    private static func makeMenuBarTitle(
        snapshot: PowerSnapshot,
        tempUnit: TempUnit,
        format: StatusBarFormat
    ) -> String {
        let pct = "\(snapshot.batteryPercent)%"
        let temp = formatTemp(snapshot.batteryTempC, unit: tempUnit)
        // System draw, not adapter capability: the negotiated USB-PD contract sits at the
        // brick's rating whenever it is plugged in and would read "140W" permanently.
        let watts = String(format: "%.0fW", snapshot.systemWatts)
        let bolt = snapshot.isCharging ? "⚡️ " : "🔋 "
        
        switch format {
        case .compact:
            return "\(bolt)\(pct) • \(temp)"
        case .full:
            return "\(bolt)\(pct) • \(temp) • \(watts)"
        case .percentOnly:
            return "\(bolt)\(pct)"
        case .wattsOnly:
            return "\(bolt)\(watts)"
        }
    }
}
