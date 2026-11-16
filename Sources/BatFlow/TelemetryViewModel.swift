import Foundation
import Combine
import SwiftUI

public enum TempUnit: String, CaseIterable, Identifiable, Codable {
    case celsius = "°C"
    case fahrenheit = "°F"

    public var id: String { rawValue }
}

extension Notification.Name {
    static let batFlowHotKeySettingChanged = Notification.Name("BatFlowHotKeySettingChanged")
}

@MainActor
public final class TelemetryViewModel: ObservableObject {
    @Published public private(set) var currentSnapshot: PowerSnapshot
    @Published public private(set) var history: [PowerSnapshot] = []
    /// Per-app estimates; `nil` until two samples have been taken since opening.
    @Published private(set) var appEstimates: [AppPowerEstimate]?

    /// True while the notch panel is open. The full poll (history, per-app
    /// sampling) only runs while this is set; otherwise a slow poll feeds the
    /// readout beside the notch.
    public var isNotchVisible: Bool = false {
        didSet {
            guard isNotchVisible != oldValue else { return }
            if isNotchVisible {
                refresh()
            } else {
                appSampler.reset()
                appEstimates = nil
            }
            startTimer()
        }
    }

    @AppStorage("tempUnit") public var tempUnit: TempUnit = .celsius
    @AppStorage("pollingInterval") public var pollingInterval: Double = 2.0 {
        didSet { if isNotchVisible { startTimer() } }
    }
    @AppStorage("notchOpensOnHover") public var notchOpensOnHover: Bool = true
    @AppStorage("notchHotKeyEnabled") public var notchHotKeyEnabled: Bool = true {
        didSet { NotificationCenter.default.post(name: .batFlowHotKeySettingChanged, object: nil) }
    }
    @AppStorage("showsNotchPower") public var showsNotchPower: Bool = true {
        didSet { if !isNotchVisible { startTimer() } }
    }

    private var timerCancellable: AnyCancellable?
    private let service = PowerTelemetryService.shared
    private let appSampler = AppPowerSampler()
    /// Recent system-power readings, open or closed, used to find the idle floor.
    private var floorSamples: [(time: Date, watts: Double)] = []

    /// Samples kept for the sparkline (about 6 minutes at the default 2 s interval).
    private static let historyLimit = 180
    private static let closedInterval: TimeInterval = 5
    private static let floorWindow: TimeInterval = 30 * 60
    private static let typicalIdleWatts: Double = 5

    public init() {
        currentSnapshot = service.fetchSnapshot()
        recordFloorSample(currentSnapshot)
        startTimer()
    }

    /// The lowest system draw seen recently (display, radios, the always-on
    /// background), capped at a typical laptop idle so a freshly launched app,
    /// which has only seen busy samples, doesn't hide everything in the floor.
    /// What sits above it is what running apps are adding.
    var idleFloorWatts: Double {
        min(floorSamples.map(\.watts).min() ?? 0, Self.typicalIdleWatts)
    }

    private func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        if isNotchVisible {
            timerCancellable = Timer.publish(every: pollingInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.refresh() }
        } else if showsNotchPower {
            timerCancellable = Timer.publish(every: Self.closedInterval, tolerance: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.refreshClosed() }
        }
    }

    private func refreshClosed() {
        let snap = service.fetchSnapshot()
        currentSnapshot = snap
        recordFloorSample(snap)
    }

    private func refresh() {
        let snap = service.fetchSnapshot()
        currentSnapshot = snap
        recordFloorSample(snap)
        history.append(snap)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
        let active = max(0, snap.systemWatts - idleFloorWatts)
        if let estimates = appSampler.sample(activeWatts: active) {
            appEstimates = estimates
        }
    }

    private func recordFloorSample(_ snap: PowerSnapshot) {
        guard snap.systemWatts > 0 else { return }
        let now = Date()
        floorSamples.append((now, snap.systemWatts))
        let cutoff = now.addingTimeInterval(-Self.floorWindow)
        if let first = floorSamples.first, first.time < cutoff {
            floorSamples.removeAll { $0.time < cutoff }
        }
    }
    public func formattedTemp(_ tempC: Double) -> String {
        switch tempUnit {
        case .celsius:
            return String(format: "%.1f°C", tempC)
        case .fahrenheit:
            return String(format: "%.1f°F", tempC * 9.0 / 5.0 + 32.0)
        }
    }
}
