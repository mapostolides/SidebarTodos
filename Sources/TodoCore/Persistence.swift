import Foundation

/// Stores everything in one human-readable JSON file, written atomically on every change.
public struct TodoPersistence: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SidebarTodos", isDirectory: true)
            .appendingPathComponent("todos.json")
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .secondsSince1970 // exact round-trip (ISO-8601 drops sub-seconds)
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    /// Missing file -> starter data. Unreadable file -> moved aside (never deleted) and starter data returned.
    public func load() -> TodoData {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .starter() }
        do {
            let raw = try Data(contentsOf: url)
            var data = try Self.decoder().decode(TodoData.self, from: raw)
            if data.lists.isEmpty { data = .starter() }
            if data.activeList == nil || data.list(data.activeListID ?? UUID()) == nil {
                data.activeListID = data.lists.first?.id
            }
            return data
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = url.deletingLastPathComponent().appendingPathComponent("todos.unreadable-\(stamp).json")
            try? fm.moveItem(at: url, to: aside)
            return .starter()
        }
    }

    public func save(_ data: TodoData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let raw = try Self.encoder().encode(data)
        try raw.write(to: url, options: .atomic)
    }
}
