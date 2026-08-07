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

@MainActor
public final class TelemetryViewModel: ObservableObject {
    @Published public private(set) var currentSnapshot: PowerSnapshot
    @Published public private(set) var history: [PowerSnapshot] = []
    
    @AppStorage("tempUnit") public var tempUnit: TempUnit = .celsius
    @AppStorage("pollingInterval") public var pollingInterval: Double = 2.0 {
        didSet { restartTimer() }
    }
    @AppStorage("statusBarFormat") public var statusBarFormat: StatusBarFormat = .full
    @AppStorage("showHealthAndCycles") public var showHealthAndCycles: Bool = false
    
    private var timerCancellable: AnyCancellable?
    private let service = PowerTelemetryService.shared
    
    public init() {
        let initial = service.fetchSnapshot()
        self.currentSnapshot = initial
        self.history.append(initial)
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
        self.currentSnapshot = snap
        self.history.append(snap)
        
        // Retain max 180 snapshots (approx 6 minutes at 2s interval)
        if history.count > 180 {
            history.removeFirst(history.count - 180)
        }
    }
    
    public func formattedTemp(_ tempC: Double) -> String {
        switch tempUnit {
        case .celsius:
            return String(format: "%.1f°C", tempC)
        case .fahrenheit:
            let f = (tempC * 9.0 / 5.0) + 32.0
            return String(format: "%.1f°F", f)
        }
    }
    
    public var menuBarTitle: String {
        let pct = "\(currentSnapshot.batteryPercent)%"
        let temp = formattedTemp(currentSnapshot.batteryTempC)
        // System draw, not adapter capability: the negotiated USB-PD contract sits at the
        // brick's rating whenever it is plugged in and would read "140W" permanently.
        let watts = String(format: "%.0fW", currentSnapshot.systemWatts)
        let bolt = currentSnapshot.isCharging ? "⚡️ " : "🔋 "
        
        switch statusBarFormat {
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
