import AppKit
import SwiftUI
import Combine

// MARK: - Geometry

struct NotchGeometry: Equatable {
    /// Notch (or notch stand-in) rect in global screen coordinates.
    let notchRect: NSRect
    let screenFrame: NSRect
    let hasNotch: Bool

    static func current() -> NotchGeometry? {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notched ?? NSScreen.screens.first else { return nil }
        let frame = screen.frame

        if notched != nil,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            let height = screen.safeAreaInsets.top
            let rect = NSRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
            return NotchGeometry(notchRect: rect, screenFrame: frame, hasNotch: true)
        }

        // No notch: the panel grows out of the menu bar's top-centre instead.
        let menuBarHeight = max(frame.maxY - screen.visibleFrame.maxY, 24)
        let width: CGFloat = 200
        let rect = NSRect(x: frame.midX - width / 2, y: frame.maxY - menuBarHeight, width: width, height: menuBarHeight)
        return NotchGeometry(notchRect: rect, screenFrame: frame, hasNotch: false)
    }
}

// MARK: - Shared UI state

@MainActor
final class NotchState: ObservableObject {
    @Published var isExpanded = false
    @Published var showingSettings = false
    @Published var closedSize: CGSize = .zero
    @Published var openSize: CGSize = .zero
    var hasNotch = true

    static let earRadius: CGFloat = 12
    static let openContentHeight: CGFloat = 318
    static let openWidth: CGFloat = 640
}

// MARK: - Windows

/// Borderless panel that can take keyboard focus (for the New Reminder field)
/// without activating the app or stealing the menu bar.
final class NotchPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Plain AppKit view with a tracking area. Deliberately no SwiftUI so the idle
/// trigger costs nothing.
final class HoverTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var fillColor: NSColor = .clear

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        // Fully transparent pixels let the mouse fall through to windows below,
        // which would starve the tracking area. Paint an imperceptible fill.
        fillColor.setFill()
        dirtyRect.fill()
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

/// The always-on wattage readout. It widens the notch to the left, drawn in plain
/// AppKit so that refreshing it every few seconds costs next to nothing.
final class PowerPillView: NSView {
    static let width: CGFloat = 64
    /// How far the pill tucks under the hardware notch, so its flat bottom edge
    /// meets the notch's rounded corner without a gap.
    static let overlap: CGFloat = 12

    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(Self.overlap + 2)),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(watts: Double, charging: Bool) {
        let text = NSMutableAttributedString()
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let attachment = NSTextAttachment()
            attachment.image = bolt
            text.append(NSAttributedString(attachment: attachment))
            text.append(NSAttributedString(string: " "))
        }
        text.append(NSAttributedString(string: String(format: "%.1fW", watts)))
        let color: NSColor = charging ? .systemGreen : .white
        text.addAttributes([
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: color
        ], range: NSRange(location: 0, length: text.length))
        label.attributedStringValue = text
        toolTip = "System power draw"
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 8
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.minX, y: bounds.maxY))
        path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        path.line(to: NSPoint(x: bounds.maxX, y: bounds.minY))
        path.line(to: NSPoint(x: bounds.minX + radius, y: bounds.minY))
        path.appendArc(
            withCenter: NSPoint(x: bounds.minX + radius, y: bounds.minY + radius),
            radius: radius, startAngle: 270, endAngle: 180, clockwise: true
        )
        path.close()
        NSColor.black.setFill()
        path.fill()
    }
}

/// The panel never activates the app, so every click is a "first" click. Without
/// this, buttons would need two clicks whenever another app is frontmost.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Controller

@MainActor
final class NotchController: NSObject, NSWindowDelegate {
    private let viewModel: TelemetryViewModel

    private let state = NotchState()
    private var geometry: NotchGeometry?
    private var triggerWindow: NSWindow?
    private var pillWindow: NSWindow?
    private var pillView: PowerPillView?
    private var panel: NotchPanel?
    private var hostingView: FirstMouseHostingView<NotchRootView>?
    private var hotKey: GlobalHotKey?
    private var cancellables = Set<AnyCancellable>()

    private var pendingOpen: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?
    private var pendingTeardown: DispatchWorkItem?
    private var isMouseInside = false
    private var isMenuTracking = false
    /// Debug/screenshot mode: ignore mouse-exit and focus-loss.
    private var isPinned = false

    private static let shadowPadding: CGFloat = 28
    /// How long the panel lingers after the pointer leaves it.
    private static let hoverCloseDelay: TimeInterval = 1.5

    var isOpen: Bool { state.isExpanded }

    init(viewModel: TelemetryViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    func start() {
        rebuildForCurrentScreen()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.rebuildForCurrentScreen() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .batFlowHotKeySettingChanged)
            .sink { [weak self] _ in self?.updateHotKey() }
            .store(in: &cancellables)

        // A list-picker menu takes the mouse outside the panel; don't treat that as leaving.
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in self?.isMenuTracking = true }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isMenuTracking = false
                if !self.isMouseInside { self.scheduleClose(after: 0.4) }
            }
            .store(in: &cancellables)

        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updateTriggerVisibility()
                self?.updatePill()
            }
            .store(in: &cancellables)

        updateHotKey()
    }

    // MARK: Public actions

    func toggleFromHotKey() {
        if state.isExpanded {
            close()
        } else {
            open(makeKey: true)
        }
    }

    func open(makeKey: Bool = false, pinned: Bool = false) {
        guard let geometry else { return }
        pendingOpen?.cancel()
        pendingClose?.cancel()
        pendingTeardown?.cancel()
        isPinned = pinned

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(panelFrame(for: geometry), display: false)

        if hostingView == nil {
            let root = NotchRootView(
                state: state,
                viewModel: viewModel,
                onToggleSettings: { [weak self] in
                    guard let self else { return }
                    // Controls in a non-key panel draw in their grey inactive style.
                    self.panel?.makeKey()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        self.state.showingSettings.toggle()
                    }
                },
                onDismiss: { [weak self] in self?.close() }
            )
            let host = FirstMouseHostingView(rootView: root)
            host.frame = panel.contentView?.bounds ?? .zero
            host.autoresizingMask = [.width, .height]
            panel.contentView?.addSubview(host)
            hostingView = host
        }

        viewModel.isNotchVisible = true
        updatePill()
        if makeKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        // Expand on the next turn so SwiftUI animates from the closed notch size.
        DispatchQueue.main.async { [weak self] in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                self?.state.isExpanded = true
            }
        }

        // Tracking areas only report entry on movement. If the pointer slid off the
        // notch before the panel appeared, nothing would ever close it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.state.isExpanded, let geometry = self.geometry else { return }
            let shape = NSRect(
                x: geometry.notchRect.midX - NotchState.openWidth / 2,
                y: geometry.screenFrame.maxY - self.state.openSize.height,
                width: NotchState.openWidth,
                height: self.state.openSize.height
            )
            self.isMouseInside = shape.contains(NSEvent.mouseLocation)
            if !self.isMouseInside && !(self.panel?.isKeyWindow ?? false) {
                self.scheduleClose(after: Self.hoverCloseDelay)
            }
        }
    }

    func close() {
        pendingOpen?.cancel()
        pendingClose?.cancel()
        guard state.isExpanded || panel?.isVisible == true else { return }
        isPinned = false

        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            state.isExpanded = false
        }

        let teardown = DispatchWorkItem { [weak self] in
            guard let self, !self.state.isExpanded else { return }
            self.panel?.orderOut(nil)
            // Drop the SwiftUI tree so nothing keeps rendering while closed.
            self.hostingView?.removeFromSuperview()
            self.hostingView = nil
            self.state.showingSettings = false
            self.viewModel.isNotchVisible = false
            self.updatePill()
        }
        pendingTeardown = teardown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36, execute: teardown)
    }

    // MARK: Private

    private func updateHotKey() {
        if viewModel.notchHotKeyEnabled {
            if hotKey == nil {
                hotKey = GlobalHotKey { [weak self] in self?.toggleFromHotKey() }
            }
            hotKey?.register()
        } else {
            hotKey?.unregister()
        }
    }

    private func updateTriggerVisibility() {
        guard let triggerWindow else { return }
        let shouldShow = viewModel.notchOpensOnHover
        if shouldShow && !triggerWindow.isVisible {
            triggerWindow.orderFrontRegardless()
        } else if !shouldShow && triggerWindow.isVisible {
            triggerWindow.orderOut(nil)
        }
    }

    private func rebuildForCurrentScreen() {
        let newGeometry = NotchGeometry.current()
        guard newGeometry != geometry else { return }
        close()
        geometry = newGeometry
        guard let geometry = newGeometry else { return }

        state.hasNotch = geometry.hasNotch
        state.closedSize = CGSize(
            width: geometry.notchRect.width + NotchState.earRadius * 2,
            height: geometry.notchRect.height
        )
        state.openSize = CGSize(
            width: NotchState.openWidth,
            height: geometry.notchRect.height + NotchState.openContentHeight
        )

        // Over a real notch the trigger covers dead pixels. Without one, keep it a
        // thin strip at the very top edge so it doesn't eat menu-bar clicks.
        var triggerRect = geometry.notchRect
        if !geometry.hasNotch {
            triggerRect = NSRect(x: geometry.notchRect.midX - 90, y: geometry.screenFrame.maxY - 3, width: 180, height: 3)
        }

        let trigger = triggerWindow ?? makeTriggerWindow()
        trigger.setFrame(triggerRect, display: true)
        triggerWindow = trigger
        updateTriggerVisibility()

        let pill = pillWindow ?? makePillWindow()
        pill.setFrame(NSRect(
            x: geometry.notchRect.minX - PowerPillView.width + PowerPillView.overlap,
            y: geometry.notchRect.minY,
            width: PowerPillView.width,
            height: geometry.notchRect.height
        ), display: true)
        pillWindow = pill
        updatePill()
    }

    /// Shown only beside a real notch: on other screens it would be a black blob
    /// in the middle of the menu bar. Hidden while the panel covers it anyway.
    private func updatePill() {
        guard let pillWindow, let pillView else { return }
        let shouldShow = viewModel.showsNotchPower && (geometry?.hasNotch ?? false) && !viewModel.isNotchVisible
        if shouldShow {
            let snap = viewModel.currentSnapshot
            pillView.update(watts: snap.systemWatts, charging: snap.isCharging)
            if !pillWindow.isVisible { pillWindow.orderFrontRegardless() }
        } else if pillWindow.isVisible {
            pillWindow.orderOut(nil)
        }
    }

    private func makePillWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = Self.windowLevel
        window.collectionBehavior = Self.collectionBehavior
        window.isReleasedWhenClosed = false
        let view = PowerPillView()
        window.contentView = view
        pillView = view
        return window
    }

    private func panelFrame(for geometry: NotchGeometry) -> NSRect {
        let pad = Self.shadowPadding
        let width = NotchState.openWidth + pad * 2
        let height = state.openSize.height + pad
        return NSRect(
            x: geometry.notchRect.midX - width / 2,
            y: geometry.screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    private static let windowLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    private static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle
    ]

    private func makeTriggerWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.level = Self.windowLevel
        window.collectionBehavior = Self.collectionBehavior
        window.isReleasedWhenClosed = false

        let view = HoverTrackingView()
        view.fillColor = NSColor.black.withAlphaComponent(0.01)
        view.onEnter = { [weak self] in self?.triggerEntered() }
        view.onExit = { [weak self] in self?.pendingOpen?.cancel() }
        window.contentView = view
        return window
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // SwiftUI draws a shadow that follows the notch shape.
        panel.level = Self.windowLevel
        panel.collectionBehavior = Self.collectionBehavior
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }

        let tracker = HoverTrackingView()
        tracker.onEnter = { [weak self] in
            self?.isMouseInside = true
            self?.pendingClose?.cancel()
        }
        tracker.onExit = { [weak self] in
            self?.isMouseInside = false
            self?.scheduleClose(after: Self.hoverCloseDelay)
        }
        panel.contentView = tracker
        return panel
    }

    private func triggerEntered() {
        guard viewModel.notchOpensOnHover, !state.isExpanded else {
            pendingClose?.cancel()
            return
        }
        pendingOpen?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.open() }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func scheduleClose(after delay: TimeInterval) {
        guard state.isExpanded, !isPinned, !isMenuTracking, !isEditingText else { return }
        pendingClose?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isMouseInside, !self.isMenuTracking, !self.isEditingText else { return }
            self.close()
        }
        pendingClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// While the user is typing a reminder, leaving the panel must not throw it away.
    private var isEditingText: Bool {
        guard let panel, panel.isKeyWindow else { return false }
        return panel.firstResponder is NSText
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard !isPinned, !isMouseInside, !isMenuTracking else { return }
        close()
    }
}
