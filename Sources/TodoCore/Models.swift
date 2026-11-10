import Foundation

public enum ListColor: String, Codable, CaseIterable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, teal, graphite
}

public struct TodoItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool
    public var createdAt: Date
    public var completedAt: Date?

    public init(id: UUID = UUID(), title: String, isDone: Bool = false,
                createdAt: Date = Date(), completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public struct TodoList: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var color: ListColor
    /// Open items keep their manual order; done items are shown newest-first.
    public var items: [TodoItem]

    public init(id: UUID = UUID(), name: String, color: ListColor = .blue, items: [TodoItem] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.items = items
    }

    public var openItems: [TodoItem] { items.filter { !$0.isDone } }

    public var doneItems: [TodoItem] {
        items.filter(\.isDone).sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }
}

public struct TodoData: Codable, Equatable, Sendable {
    public var version: Int
    public var lists: [TodoList]
    public var activeListID: UUID?

    public init(version: Int = 1, lists: [TodoList], activeListID: UUID?) {
        self.version = version
        self.lists = lists
        self.activeListID = activeListID
    }

    public static func starter() -> TodoData {
        let welcome = TodoList(name: "My TODOs", color: .blue, items: [
            TodoItem(title: "Hover the slim tab on the left edge to open this list"),
            TodoItem(title: "Click the circle to check a TODO off"),
            TodoItem(title: "Double-click a TODO to edit it"),
        ])
        return TodoData(lists: [welcome], activeListID: welcome.id)
    }

    /// The list shown in the edge drawer (falls back to the first list).
    public var activeList: TodoList? {
        lists.first { $0.id == activeListID } ?? lists.first
    }

    public func list(_ id: UUID) -> TodoList? { lists.first { $0.id == id } }

    private func index(of listID: UUID) -> Int? { lists.firstIndex { $0.id == listID } }

    // MARK: Lists

    @discardableResult
    public mutating func addList(name: String, color: ListColor? = nil) -> UUID {
        let used = Set(lists.map(\.color))
        let pick = color ?? ListColor.allCases.first { !used.contains($0) } ?? .blue
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = TodoList(name: trimmed.isEmpty ? "New List" : trimmed, color: pick)
        lists.append(list)
        if activeListID == nil { activeListID = list.id }
        return list.id
    }

    public mutating func renameList(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = index(of: id) else { return }
        lists[i].name = trimmed
    }

    public mutating func setColor(_ color: ListColor, for id: UUID) {
        guard let i = index(of: id) else { return }
        lists[i].color = color
    }

    /// Deleting the last remaining list is refused so the edge drawer always has a list.
    @discardableResult
    public mutating func deleteList(_ id: UUID) -> Bool {
        guard lists.count > 1, let i = index(of: id) else { return false }
        lists.remove(at: i)
        if activeListID == id { activeListID = lists[min(i, lists.count - 1)].id }
        return true
    }

    public mutating func setActive(_ id: UUID) {
        guard index(of: id) != nil else { return }
        activeListID = id
    }

    public mutating func moveLists(from source: IndexSet, to destination: Int) {
        lists = lists.moving(fromOffsets: source, toOffset: destination)
    }

    // MARK: Items

    @discardableResult
    public mutating func addItem(_ title: String, to listID: UUID, atTop: Bool) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = index(of: listID) else { return nil }
        let item = TodoItem(title: trimmed)
        if atTop { lists[i].items.insert(item, at: 0) } else { lists[i].items.append(item) }
        return item.id
    }

    /// Checking moves an item to the Done section; unchecking puts it back at the end of the open items.
    public mutating func toggleItem(_ itemID: UUID, in listID: UUID, now: Date = Date()) {
        guard let i = index(of: listID),
              let j = lists[i].items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = lists[i].items.remove(at: j)
        item.isDone.toggle()
        item.completedAt = item.isDone ? now : nil
        lists[i].items.append(item)
    }

    public mutating func renameItem(_ itemID: UUID, in listID: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = index(of: listID),
              let j = lists[i].items.firstIndex(where: { $0.id == itemID }) else { return }
        lists[i].items[j].title = trimmed
    }

    public mutating func deleteItem(_ itemID: UUID, in listID: UUID) {
        guard let i = index(of: listID) else { return }
        lists[i].items.removeAll { $0.id == itemID }
    }

    public mutating func clearDone(in listID: UUID) {
        guard let i = index(of: listID) else { return }
        lists[i].items.removeAll(where: \.isDone)
    }

    /// Reorders within the open items only (offsets refer to `openItems`).
    public mutating func moveOpenItems(in listID: UUID, from source: IndexSet, to destination: Int) {
        guard let i = index(of: listID) else { return }
        let reordered = lists[i].openItems.moving(fromOffsets: source, toOffset: destination)
        lists[i].items = reordered + lists[i].items.filter(\.isDone)
    }

    public mutating func moveItem(_ itemID: UUID, from listID: UUID, to targetID: UUID) {
        guard listID != targetID, let i = index(of: listID), let t = index(of: targetID),
              let j = lists[i].items.firstIndex(where: { $0.id == itemID }) else { return }
        let item = lists[i].items.remove(at: j)
        lists[t].items.append(item)
    }
}

extension Array {
    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, without importing SwiftUI.
    public func moving(fromOffsets source: IndexSet, toOffset destination: Int) -> [Element] {
        let moved = source.sorted().map { self[$0] }
        var rest: [Element] = []
        var insertAt = destination
        for (offset, element) in enumerated() {
            if source.contains(offset) {
                if offset < destination { insertAt -= 1 }
            } else {
                rest.append(element)
            }
        }
        insertAt = Swift.max(0, Swift.min(insertAt, rest.count))
        rest.insert(contentsOf: moved, at: insertAt)
        return rest
    }
}
