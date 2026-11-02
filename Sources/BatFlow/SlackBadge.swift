import AppKit
import SwiftUI

/// Reads the badge Slack puts on its Dock icon (mentions and DMs, or "•" for
/// other unreads) from the Dock's accessibility tree. Needs Accessibility access;
/// no Slack token or workspace app.
@MainActor
final class SlackBadgeStore: ObservableObject {
    static let shared = SlackBadgeStore()

    static let bundleID = "com.tinyspeck.slackmacgap"
    static let refreshInterval: TimeInterval = 10

    /// nil when Slack isn't running or shows no badge.
    @Published private(set) var label: String?
    @Published private(set) var isRunning = false
    @Published private(set) var hasAccessibilityAccess = AXIsProcessTrusted()

    private(set) lazy var appIcon: NSImage? = {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }()

    func refresh() async {
        hasAccessibilityAccess = AXIsProcessTrusted()
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        isRunning = running
        guard running, hasAccessibilityAccess,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let slackURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID)
        else {
            label = nil
            return
        }
        let dockPID = dock.processIdentifier
        let value = await Task.detached(priority: .utility) {
            Self.readDockBadge(dockPID: dockPID, appURL: slackURL)
        }.value
        if value != label { label = value }
    }

    /// Shows the system prompt that sends the user to Privacy & Security › Accessibility.
    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibilityAccess = AXIsProcessTrustedWithOptions(options)
    }

    func openSlack() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Dock → AXList → one AXDockItem per app. The item's AXURL identifies the app
    /// (its title is localised), and AXStatusLabel holds the badge text.
    nonisolated private static func readDockBadge(dockPID: pid_t, appURL: URL) -> String? {
        let dock = AXUIElementCreateApplication(dockPID)
        for list in children(of: dock) where role(of: list) == kAXListRole {
            for item in children(of: list) {
                guard let url = attribute(item, kAXURLAttribute) as? URL,
                      url.standardizedFileURL.path == appURL.standardizedFileURL.path else { continue }
                let label = attribute(item, "AXStatusLabel") as? String
                return (label?.isEmpty ?? true) ? nil : label
            }
        }
        return nil
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    nonisolated private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    nonisolated private static func role(of element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute) as? String
    }
}

/// Slack's icon with its Dock badge, for the notch header. Hidden when Slack isn't running.
struct SlackBadgeView: View {
    @ObservedObject private var store = SlackBadgeStore.shared
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        // A container that always exists, so `.task` runs even while Slack is closed.
        HStack(spacing: 0) {
            if store.isRunning {
                Button {
                    if store.hasAccessibilityAccess {
                        store.openSlack()
                        onOpen()
                    } else {
                        store.requestAccessibilityAccess()
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let icon = store.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        if !store.hasAccessibilityAccess {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                        } else if let label = store.label {
                            Text(label)
                                .font(.system(size: 10.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, label.count > 1 ? 5 : 0)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Capsule().fill(Color.red))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(isHovering ? 0.12 : 0)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .help(helpText)
            }
        }
        // Polls only while the notch is open; cancelled when the panel is torn down.
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(SlackBadgeStore.refreshInterval))
            }
        }
    }

    private var helpText: String {
        if !store.hasAccessibilityAccess {
            return "Click to allow Accessibility access so BatFlow can read Slack's unread badge"
        }
        switch store.label {
        case nil: return "Slack: no unread mentions"
        case "•": return "Slack: unread messages"
        case let count?: return "Slack: \(count) unread mentions and DMs"
        }
    }
}
