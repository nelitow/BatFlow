import SwiftUI
import AppKit

/// Settings shown in place of the cards when the header's gear is clicked.
/// Laid out like System Settings' grouped rows.
struct NotchSettingsView: View {
    @ObservedObject var viewModel: TelemetryViewModel
    @ObservedObject private var reminders = RemindersStore.shared
    @ObservedObject private var slack = SlackBadgeStore.shared
    @ObservedObject private var linear = LinearStore.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 10) {
                SettingsGroup(title: "Notch") {
                    SettingsRow("Open on Hover") {
                        Toggle("", isOn: $viewModel.notchOpensOnHover)
                            // Hover and the shortcut can't both be off, or there'd be no way back in.
                            .disabled(!viewModel.notchHotKeyEnabled)
                    }
                    SettingsRow("Keyboard Shortcut  \(GlobalHotKey.displayString)") {
                        Toggle("", isOn: $viewModel.notchHotKeyEnabled)
                            .disabled(!viewModel.notchOpensOnHover)
                    }
                }
                SettingsGroup(title: "Power") {
                    SettingsRow("Temperature") {
                        Picker("", selection: $viewModel.tempUnit) {
                            ForEach(TempUnit.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 96)
                    }
                    SettingsRow("Update Every") {
                        Picker("", selection: $viewModel.pollingInterval) {
                            Text("1 second").tag(1.0)
                            Text("2 seconds").tag(2.0)
                            Text("5 seconds").tag(5.0)
                        }
                        .frame(width: 110)
                    }
                }
            }

            VStack(spacing: 10) {
                SettingsGroup(title: "Connections") {
                    SettingsRow("Reminders", status: remindersStatus) {
                        switch reminders.access {
                        case .granted: EmptyView()
                        case .notDetermined: Button("Allow") { reminders.requestAccess() }
                        case .denied: Button("Open Settings") { reminders.openPrivacySettings() }
                        }
                    }
                    SettingsRow("Slack Unreads", status: slack.hasAccessibilityAccess ? "Reading Slack's Dock badge" : "Needs Accessibility access") {
                        if !slack.hasAccessibilityAccess {
                            Button("Allow") { slack.requestAccessibilityAccess() }
                        }
                    }
                    SettingsRow("Linear", status: LinearStore.locateCLI() == nil ? "Linear CLI not installed" : "Using the linear CLI") {
                        EmptyView()
                    }
                }

                HStack {
                    Text("BatFlow \(version)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Quit BatFlow") { NSApp.terminate(nil) }
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
        .controlSize(.small)
        .toggleStyle(.switch)
        .labelsHidden()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var remindersStatus: String {
        switch reminders.access {
        case .granted: return reminders.selectedList.map { "Showing “\($0.title)”" } ?? "Connected"
        case .notDetermined: return "Not connected"
        case .denied: return "Access denied"
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.075))
            )
        }
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let status: String?
    @ViewBuilder let accessory: () -> Accessory

    init(_ title: String, status: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.status = status
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12))
                if let status {
                    Text(status)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5).padding(.leading, 12)
        }
    }
}
