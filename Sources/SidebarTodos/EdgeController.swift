import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating panel that floats over every Space (including full-screen apps).
final class EdgePanel: NSPanel {
    var allowsKey = false
    var onCancel: (() -> Void)?

    init(rect: NSRect) {
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Reports mouse enter/exit even while another app is active.
final class HoverTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil // the whole tab is one click target
    }
}

final class EdgeUIState: ObservableObject {
    @Published var tabHovered = false
    @Published var drawerOpen = false
}

@MainActor
final class EdgeController {
    static let tabWidth: CGFloat = 12
    static let drawerWidth: CGFloat = 340
    static let drawerMargin: CGFloat = 8
    static let hoverDelay: TimeInterval = 0.06
    /// How close (in points) the cursor must come to the tab to open the drawer (~2 cursor lengths).
    static let proximity: CGFloat = 48
    static let closeDelay: TimeInterval = 0.4

    private let store: Store
    private let settings: AppSettings
    private let openMainWindow: () -> Void
    let ui = EdgeUIState()

    private var tab: EdgePanel!
    private var drawer: EdgePanel!
    private var pendingOpen: DispatchWorkItem?
    private var pollTimer: Timer?
    private var outsideSince: Date?
    private var cancellables = Set<AnyCancellable>()

    init(store: Store, settings: AppSettings, openMainWindow: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.openMainWindow = openMainWindow
        buildTab()
        buildDrawer()
        layout()
        tab.orderFrontRegardless()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &cancellables)
        settings.$displayID.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &cancellables)

        // Proximity detection: poll the cursor position (needs no permissions and sees every way
        // the cursor can move; reading it 20x/s costs effectively nothing).
        let proximityTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.cursorMoved() }
        }
        RunLoop.main.add(proximityTimer, forMode: .common)
    }

    /// The tab plus a margin around it; entering this zone opens the drawer.
    private var proximityZone: NSRect {
        let f = tab.frame
        return NSRect(x: f.minX - 2, y: f.minY - Self.proximity,
                      width: f.width + Self.proximity + 2, height: f.height + 2 * Self.proximity)
    }

    var isOpen: Bool { ui.drawerOpen }

    private var screen: NSScreen {
        if settings.displayID != 0,
           let s = NSScreen.screens.first(where: { $0.displayID == settings.displayID }) { return s }
        return NSScreen.screens.first ?? NSScreen.main!
    }

    // MARK: Building

    private func buildTab() {
        tab = EdgePanel(rect: NSRect(x: 0, y: 0, width: Self.tabWidth, height: 300))
        let tracker = HoverTrackingView()
        let host = NSHostingView(rootView: TabHandleView(store: store, ui: ui))
        host.translatesAutoresizingMaskIntoConstraints = false
        tracker.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: tracker.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: tracker.trailingAnchor),
            host.topAnchor.constraint(equalTo: tracker.topAnchor),
            host.bottomAnchor.constraint(equalTo: tracker.bottomAnchor),
        ])
        tracker.onEnter = { [weak self] in self?.cursorMoved() }
        tracker.onExit = { [weak self] in self?.cursorMoved() }
        tracker.onClick = { [weak self] in self?.open() }
        tab.contentView = tracker
    }

    private func buildDrawer() {
        drawer = EdgePanel(rect: NSRect(x: 0, y: 0, width: Self.drawerWidth, height: 600))
        drawer.allowsKey = true
        drawer.becomesKeyOnlyIfNeeded = true // hovering never steals keyboard focus; clicking a text field does
        drawer.hasShadow = true
        drawer.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        drawer.onCancel = { [weak self] in self?.close() }

        let content = DrawerView(store: store, settings: settings,
                                 openApp: { [weak self] in self?.close(); self?.openMainWindow() },
                                 close: { [weak self] in self?.close() })
        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false

        let glass: NSView
        if #available(macOS 26.0, *) {
            let g = NSGlassEffectView()
            g.cornerRadius = 20
            g.style = .regular
            g.contentView = host
            glass = g
        } else {
            let v = NSVisualEffectView()
            v.material = .popover
            v.blendingMode = .behindWindow
            v.state = .active
            v.maskImage = Self.roundedMask(radius: 20)
            v.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: v.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: v.trailingAnchor),
                host.topAnchor.constraint(equalTo: v.topAnchor),
                host.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            ])
            glass = v
        }
        drawer.contentView = glass
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: Layout

    func layout() {
        // The tab spans exactly the drawer's vertical extent.
        let vf = screen.visibleFrame
        let d = drawerFrame()
        tab.setFrame(NSRect(x: vf.minX, y: d.minY, width: Self.tabWidth, height: d.height), display: true)
        if isOpen { drawer.setFrame(drawerFrame(), display: true) }
    }

    private func drawerFrame() -> NSRect {
        let vf = screen.visibleFrame
        let height = min(vf.height - 2 * Self.drawerMargin, max(440, (vf.height * 0.8).rounded()))
        return NSRect(x: vf.minX + Self.drawerMargin, y: (vf.midY - height / 2).rounded(),
                      width: Self.drawerWidth, height: height)
    }

    // MARK: Hover behaviour

    private func cursorMoved() {
        let near = proximityZone.contains(NSEvent.mouseLocation) && NSEvent.pressedMouseButtons == 0
        if ui.tabHovered != near { ui.tabHovered = near }
        guard near else {
            pendingOpen?.cancel()
            pendingOpen = nil
            return
        }
        guard !isOpen, pendingOpen == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingOpen = nil
                if self.proximityZone.contains(NSEvent.mouseLocation) { self.open() }
            }
        }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverDelay, execute: work)
    }

    func toggle() { isOpen ? close() : open() }

    func open() {
        pendingOpen?.cancel()
        pendingOpen = nil
        guard !isOpen else { return }
        ui.drawerOpen = true
        outsideSince = nil
        let final = drawerFrame()
        drawer.setFrame(final.offsetBy(dx: -18, dy: 0), display: false)
        drawer.alphaValue = 0
        drawer.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            drawer.animator().setFrame(final, display: true)
            drawer.animator().alphaValue = 1
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .default) // pauses while a menu is open, so menus don't close the drawer
        pollTimer = timer
    }

    func close() {
        guard isOpen else { return }
        ui.drawerOpen = false
        pollTimer?.invalidate()
        pollTimer = nil
        let target = drawer.frame.offsetBy(dx: -18, dy: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            drawer.animator().setFrame(target, display: true)
            drawer.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isOpen else { return }
                self.drawer.orderOut(nil)
            }
        })
    }

    /// Typing into a field keeps the drawer open even if the mouse wanders off.
    private var isEditingWithText: Bool {
        guard drawer.isKeyWindow, let editor = drawer.firstResponder as? NSTextView else { return false }
        return !editor.string.isEmpty
    }

    private func poll() {
        let mouse = NSEvent.mouseLocation
        let inside = drawer.frame.insetBy(dx: -14, dy: -14).contains(mouse)
            || proximityZone.contains(mouse)
        if inside || isEditingWithText || NSEvent.pressedMouseButtons != 0 {
            outsideSince = nil
            return
        }
        if let since = outsideSince {
            if Date().timeIntervalSince(since) >= Self.closeDelay { close() }
        } else {
            outsideSince = Date()
        }
    }
}
