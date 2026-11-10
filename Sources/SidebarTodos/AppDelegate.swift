import AppKit
import SwiftUI
import TodoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = Store()
    let settings = AppSettings()
    let selection = MainSelection()
    private var edge: EdgeController!
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        settings.performFirstRunSetup()
        edge = EdgeController(store: store, settings: settings) { [weak self] in self?.showMainWindow() }
        if !launchedAsLoginItem() { showMainWindow() }
        if let dir = ProcessInfo.processInfo.environment["SIDEBARTODOS_SNAPSHOT_DIR"] { snapshot(to: dir) }
    }

    /// Dev aid: opens the drawer and main window, then writes PNGs of both (no screen-recording permission needed).
    private func snapshot(to dir: String) {
        edge.open()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            var windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 100 }
            windows.sort { $0.frame.width < $1.frame.width }
            for (i, w) in windows.enumerated() {
                guard let view = w.contentView?.superview ?? w.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = URL(fileURLWithPath: dir).appendingPathComponent("window\(i).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    // MARK: Windows

    @objc func showMainWindow() {
        if mainWindow == nil {
            let root = MainView(store: store, settings: settings, selection: selection)
            let controller = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: controller)
            window.title = "Sidebar Todos"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 780, height: 560))
            window.center()
            window.setFrameAutosaveName("SidebarTodosMain")
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(
                rootView: SettingsView(settings: settings, dataURL: store.persistence.url))
            let window = NSWindow(contentViewController: controller)
            window.title = "Sidebar Todos Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func newList() {
        showMainWindow()
        var newID: UUID?
        store.update { newID = $0.addList(name: "New List") }
        selection.listID = newID
        selection.renameRequest = newID
    }

    @objc func toggleDrawer() { edge.toggle() }
    @objc func biggerText() { settings.biggerText() }
    @objc func smallerText() { settings.smallerText() }
    @objc func resetText() { settings.resetText() }

    // MARK: Menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Sidebar Todos",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Sidebar Todos", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Sidebar Todos", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New List", action: #selector(newList), keyEquivalent: "n")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Show Edge Drawer", action: #selector(toggleDrawer), keyEquivalent: "e")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Larger Text", action: #selector(biggerText), keyEquivalent: "+")
        let plusAlias = viewMenu.addItem(withTitle: "Larger Text", action: #selector(biggerText), keyEquivalent: "=")
        plusAlias.isHidden = true // Cmd-= also works without Shift
        plusAlias.allowsKeyEquivalentWhenHidden = true
        viewMenu.addItem(withTitle: "Smaller Text", action: #selector(smallerText), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Default Text Size", action: #selector(resetText), keyEquivalent: "0")
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Sidebar Todos", action: #selector(showMainWindow), keyEquivalent: "1")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        // Items with a nil target reach this delegate through the responder chain (NSApp -> delegate).
        return main
    }
}
