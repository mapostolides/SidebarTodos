import Foundation
import Testing
@testable import TodoCore

private func makeData() -> (TodoData, UUID) {
    var d = TodoData(lists: [], activeListID: nil)
    let id = d.addList(name: "Work")
    return (d, id)
}

@Test func addItemTrimsAndRejectsEmpty() {
    var (d, id) = makeData()
    #expect(d.addItem("   ", to: id, atTop: true) == nil)
    d.addItem("  a  ", to: id, atTop: false)
    d.addItem("b", to: id, atTop: false)
    d.addItem("top", to: id, atTop: true)
    #expect(d.list(id)!.openItems.map(\.title) == ["top", "a", "b"])
}

@Test func checkedItemsSinkAndUncheckReturnsToEndOfOpen() {
    var (d, id) = makeData()
    let a = d.addItem("a", to: id, atTop: false)!
    let b = d.addItem("b", to: id, atTop: false)!
    d.addItem("c", to: id, atTop: false)
    d.toggleItem(a, in: id, now: Date(timeIntervalSince1970: 1))
    d.toggleItem(b, in: id, now: Date(timeIntervalSince1970: 2))
    #expect(d.list(id)!.openItems.map(\.title) == ["c"])
    #expect(d.list(id)!.doneItems.map(\.title) == ["b", "a"]) // newest first
    d.toggleItem(a, in: id)
    #expect(d.list(id)!.openItems.map(\.title) == ["c", "a"])
    #expect(d.list(id)!.openItems.last!.completedAt == nil)
}

@Test func reorderOpenItemsIgnoresInterleavedDoneItems() {
    var (d, id) = makeData()
    let a = d.addItem("a", to: id, atTop: false)!
    d.addItem("b", to: id, atTop: false)
    d.addItem("c", to: id, atTop: false)
    d.addItem("x", to: id, atTop: true)
    d.toggleItem(a, in: id)
    // open = [x, b, c]; move c to the front
    d.moveOpenItems(in: id, from: IndexSet(integer: 2), to: 0)
    #expect(d.list(id)!.openItems.map(\.title) == ["c", "x", "b"])
    #expect(d.list(id)!.doneItems.map(\.title) == ["a"])
}

@Test func movingMatchesSwiftUISemantics() {
    let a = [0, 1, 2, 3, 4]
    #expect(a.moving(fromOffsets: IndexSet(integer: 0), toOffset: 5) == [1, 2, 3, 4, 0])
    #expect(a.moving(fromOffsets: IndexSet(integer: 4), toOffset: 0) == [4, 0, 1, 2, 3])
    #expect(a.moving(fromOffsets: IndexSet([1, 3]), toOffset: 5) == [0, 2, 4, 1, 3])
    #expect(a.moving(fromOffsets: IndexSet(integer: 2), toOffset: 2) == a)
}

@Test func deletingActiveListReassignsAndLastListIsProtected() {
    var (d, work) = makeData()
    let home = d.addList(name: "Home")
    d.setActive(home)
    let deletedHome = d.deleteList(home)
    #expect(deletedHome)
    #expect(d.activeListID == work)
    let deletedLast = d.deleteList(work)
    #expect(!deletedLast)
    #expect(d.lists.count == 1)
}

@Test func newListsGetDistinctColorsAndClearDoneWorks() {
    var (d, work) = makeData()
    let home = d.addList(name: "")
    #expect(d.list(home)!.name == "New List")
    #expect(d.list(home)!.color != d.list(work)!.color)
    let x = d.addItem("x", to: work, atTop: true)!
    d.toggleItem(x, in: work)
    d.moveItem(x, from: work, to: home)
    #expect(d.list(work)!.items.isEmpty)
    d.clearDone(in: home)
    #expect(d.list(home)!.items.isEmpty)
}

@Test func persistenceRoundTripAndCorruptRecovery() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let p = TodoPersistence(url: dir.appendingPathComponent("todos.json"))
    #expect(p.load().lists.first?.name == "My TODOs") // missing file -> starter
    var (d, id) = makeData()
    d.addItem("persist me", to: id, atTop: true)
    try p.save(d)
    // Epoch-seconds doubles keep sub-millisecond precision, not bit-exact Dates.
    let loaded = p.load()
    #expect(loaded.lists.map(\.id) == d.lists.map(\.id))
    #expect(loaded.activeListID == d.activeListID)
    let a = loaded.lists[0].items[0], b = d.lists[0].items[0]
    #expect(a.id == b.id && a.title == b.title && a.isDone == b.isDone)
    #expect(abs(a.createdAt.timeIntervalSince(b.createdAt)) < 0.001)
    try Data("{not json".utf8).write(to: p.url)
    #expect(p.load().lists.first?.name == "My TODOs")
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(names.contains { $0.hasPrefix("todos.unreadable-") }) // bad file kept, not deleted
}
