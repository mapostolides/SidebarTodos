import AppKit
import ServiceManagement
import SwiftUI
import TodoCore

/// Observable wrapper around `TodoData`; every change is saved to disk immediately.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var data: TodoData
    let persistence: TodoPersistence

    init(persistence: TodoPersistence = TodoPersistence(url: TodoPersistence.defaultURL)) {
        self.persistence = persistence
        self.data = persistence.load()
        save() // make sure the file exists from the first launch
    }

    func update(_ change: (inout TodoData) -> Void) {
        var copy = data
        change(&copy)
        guard copy != data else { return }
        data = copy
        save()
    }

    func list(_ id: UUID) -> TodoList? { data.list(id) }

    private func save() {
        do { try persistence.save(data) } catch {
            NSLog("SidebarTodos: could not save %@: %@", persistence.url.path, String(describing: error))
        }
    }
}

extension ListColor {
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .graphite: return .gray
        }
    }

    var label: String { rawValue.capitalized }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var newItemsAtTop: Bool {
        didSet { defaults.set(newItemsAtTop, forKey: "newItemsAtTop") }
    }

    /// 0 = the main display (the one with the menu bar).
    @Published var displayID: UInt32 {
        didSet { defaults.set(Int(displayID), forKey: "displayID") }
    }

    static let fontSizeRange: ClosedRange<Double> = 10...24
    static let defaultFontSize: Double = 13

    /// Point size of TODO text (the main window uses it +1 pt).
    @Published var fontSize: Double {
        didSet {
            let clamped = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
            if clamped != fontSize { fontSize = clamped; return }
            defaults.set(fontSize, forKey: "fontSize")
        }
    }

    func biggerText() { fontSize += 1 }
    func smallerText() { fontSize -= 1 }
    func resetText() { fontSize = Self.defaultFontSize }

    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNote: String?

    init() {
        newItemsAtTop = defaults.object(forKey: "newItemsAtTop") as? Bool ?? true
        displayID = UInt32(truncatingIfNeeded: defaults.integer(forKey: "displayID"))
        fontSize = defaults.object(forKey: "fontSize") as? Double ?? Self.defaultFontSize
        refreshLoginStatus()
    }

    /// Turn launch-at-login on the very first time the app runs (it was requested as a feature).
    func performFirstRunSetup() {
        guard !defaults.bool(forKey: "didFirstRunSetup"), Bundle.main.bundleIdentifier != nil else { return }
        defaults.set(true, forKey: "didFirstRunSetup")
        setLaunchAtLogin(true)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginNote = nil
        } catch {
            loginNote = "Could not change the login item: \(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    func refreshLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
        case .requiresApproval:
            launchAtLogin = true
            loginNote = "Approve Sidebar Todos in System Settings > General > Login Items."
        default:
            launchAtLogin = false
        }
    }
}
