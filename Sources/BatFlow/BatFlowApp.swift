import SwiftUI
import AppKit
import Combine

@main
struct BatFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var viewModel: TelemetryViewModel?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let vm = TelemetryViewModel()
        self.viewModel = vm
        
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 680)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView(viewModel: vm))
        self.popover = popover
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = vm.menuBarTitle
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        self.statusItem = item
        
        // Observe view model title updates
        vm.$currentSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, let button = self.statusItem?.button, let vm = self.viewModel else { return }
                button.title = vm.menuBarTitle
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
