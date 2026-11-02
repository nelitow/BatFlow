import SwiftUI
import AppKit

@main
struct BatFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let notch = NotchController(viewModel: TelemetryViewModel())
        notch.start()
        notchController = notch

        // Opens the panel pinned at launch, for screenshots and UI review.
        if CommandLine.arguments.contains("--open-notch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                notch.open(pinned: true)
            }
        }
    }

    /// With no menu-bar item, opening BatFlow again (Finder, Spotlight, Dock) is the
    /// way back in if hover and the shortcut are both unavailable.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        notchController?.open(makeKey: true)
        return false
    }
}
