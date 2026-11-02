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

    /// True while the notch panel is open. Nothing shows telemetry while it is
    /// closed, so the poll timer only runs while this is set.
    public var isNotchVisible: Bool = false {
        didSet {
            guard isNotchVisible != oldValue else { return }
            if isNotchVisible {
                refresh()
                startTimer()
            } else {
                timerCancellable?.cancel()
                timerCancellable = nil
            }
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

    private var timerCancellable: AnyCancellable?
    private let service = PowerTelemetryService.shared

    /// Samples kept for the sparkline (about 6 minutes at the default 2 s interval).
    private static let historyLimit = 180

    public init() {
        currentSnapshot = service.fetchSnapshot()
    }

    private func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: pollingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let snap = service.fetchSnapshot()
        currentSnapshot = snap
        history.append(snap)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
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
