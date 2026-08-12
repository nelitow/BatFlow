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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var viewModel: TelemetryViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var lastMenuBarTitle: String = ""
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let vm = TelemetryViewModel()
        self.viewModel = vm
        
        // Do not attach PopoverView here. Instantiating NSHostingController at launch
        // loads the SwiftUI tree; once the popover has been opened once, a
        // `repeatForever` animation kept driving layout/render at ~20% CPU even
        // after close. Content is created on open and torn down on close.
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 680)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        self.popover = popover
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = vm.menuBarTitle
            lastMenuBarTitle = vm.menuBarTitle
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        self.statusItem = item
        
        vm.$menuBarTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                guard let self, let button = self.statusItem?.button else { return }
                guard title != self.lastMenuBarTitle else { return }
                self.lastMenuBarTitle = title
                button.title = title
            }
            .store(in: &cancellables)
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover = popover, let vm = viewModel else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            vm.isPopoverVisible = true
            ensurePopoverContent(viewModel: vm)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    private func ensurePopoverContent(viewModel: TelemetryViewModel) {
        guard popover?.contentViewController == nil else { return }
        popover?.contentViewController = NSHostingController(rootView: PopoverView(viewModel: viewModel))
    }
    
    private func tearDownPopoverContent() {
        viewModel?.isPopoverVisible = false
        // Drop the hosting controller so SwiftUI tears down TimelineView display links.
        popover?.contentViewController = nil
    }
    
    // MARK: - NSPopoverDelegate
    
    func popoverDidClose(_ notification: Notification) {
        tearDownPopoverContent()
    }
}
