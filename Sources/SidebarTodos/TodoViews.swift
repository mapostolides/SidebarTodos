import SwiftUI
import TodoCore

/// The slim tab on the screen edge: a colored rail with an open-TODO count badge.
struct TabHandleView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: EdgeUIState

    var body: some View {
        let list = store.data.activeList
        let tint = list?.color.color ?? .accentColor
        let count = list?.openItems.count ?? 0
        let lit = ui.tabHovered || ui.drawerOpen
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 6, topTrailingRadius: 6)
                .fill(.regularMaterial)
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 6, topTrailingRadius: 6)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            Capsule()
                .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: lit ? 5 : 4)
                .padding(.vertical, 14)
            if count > 0 {
                Text(count > 99 ? "99" : "\(count)")
                    .font(.system(size: count > 9 ? 7.5 : 8.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 11, height: 15)
                    .background(Capsule().fill(tint))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            }
        }
        .opacity(lit ? 1 : 0.8)
        .animation(.easeOut(duration: 0.15), value: lit)
        .help(list.map { "\($0.name): \(count) open" } ?? "Sidebar Todos")
    }
}

/// Text field that adds a TODO on Return.
struct AddTodoField: View {
    @ObservedObject var store: Store
    @ObservedObject var settings: AppSettings
    let listID: UUID
    let tint: Color
    var large = false
    @State private var text = ""
    @FocusState private var focused: Bool
    private var textSize: CGFloat { settings.fontSize + (large ? 1 : 0) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: textSize + 3))
                .foregroundStyle(tint)
            TextField("Add a TODO", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: textSize))
                .focused($focused)
                .onSubmit(add)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, large ? 9 : 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(focused ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? tint.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func add() {
        let title = text
        withAnimation(.snappy(duration: 0.2)) {
            store.update { $0.addItem(title, to: listID, atTop: settings.newItemsAtTop) }
        }
        text = ""
        focused = true
    }
}

struct TodoRow: View {
    @ObservedObject var store: Store
    let item: TodoItem
    let listID: UUID
    let tint: Color
    var large = false
    var textSize: CGFloat = 13
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Button(action: toggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: textSize + 2, weight: .regular))
                    .foregroundStyle(item.isDone ? tint : Color.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Mark as not done" : "Mark as done")
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + textSize * 0.28 }

            if editing {
                TextField("TODO", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: textSize))
                    .focused($editFocused)
                    .onSubmit(commit)
                    .onChange(of: editFocused) { _, isFocused in if !isFocused { commit() } }
                    .onExitCommand { editing = false }
            } else {
                Text(item.title)
                    .font(.system(size: textSize))
                    .strikethrough(item.isDone, color: .secondary)
                    .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginEdit)
            }

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    store.update { $0.deleteItem(item.id, in: listID) }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: max(11, textSize)))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovering && !editing ? 1 : 0)
            .help("Delete")
        }
        .padding(.vertical, large ? 5 : 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button(item.isDone ? "Mark as Not Done" : "Mark as Done", action: toggle)
            Button("Edit", action: beginEdit)
            let others = store.data.lists.filter { $0.id != listID }
            if !others.isEmpty {
                Menu("Move to") {
                    ForEach(others) { other in
                        Button(other.name) {
                            store.update { $0.moveItem(item.id, from: listID, to: other.id) }
                        }
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                store.update { $0.deleteItem(item.id, in: listID) }
            }
        }
    }

    private func toggle() {
        withAnimation(.snappy(duration: 0.25)) {
            store.update { $0.toggleItem(item.id, in: listID) }
        }
    }

    private func beginEdit() {
        draft = item.title
        editing = true
        DispatchQueue.main.async { editFocused = true }
    }

    private func commit() {
        guard editing else { return }
        editing = false
        store.update { $0.renameItem(item.id, in: listID, to: draft) }
    }
}

/// The TODO list body shared by the edge drawer and the main window.
struct TodoListContent: View {
    @ObservedObject var store: Store
    @ObservedObject var settings: AppSettings
    let listID: UUID
    var large = false
    @AppStorage("doneCollapsed") private var doneCollapsed = false

    var body: some View {
        if let list = store.list(listID) {
            let tint = list.color.color
            let open = list.openItems
            let done = list.doneItems
            VStack(spacing: 8) {
                AddTodoField(store: store, settings: settings, listID: listID, tint: tint, large: large)
                    .padding(.horizontal, large ? 20 : 14)

                List {
                    Section {
                        ForEach(open) { item in
                            TodoRow(store: store, item: item, listID: listID, tint: tint, large: large,
                                    textSize: settings.fontSize + (large ? 1 : 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .onMove { from, to in
                            store.update { $0.moveOpenItems(in: listID, from: from, to: to) }
                        }
                        if open.isEmpty {
                            emptyState(tint: tint, hasDone: !done.isEmpty)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }

                    if !done.isEmpty {
                        Section {
                            if !doneCollapsed {
                                ForEach(done) { item in
                                    TodoRow(store: store, item: item, listID: listID, tint: tint, large: large,
                                    textSize: settings.fontSize + (large ? 1 : 0))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                            }
                        } header: {
                            doneHeader(count: done.count)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 22)
                .padding(.horizontal, large ? 10 : 4)
            }
        }
    }

    private func doneHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { doneCollapsed.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(doneCollapsed ? 0 : 90))
                    Text("Done")
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Clear") {
                withAnimation(.snappy(duration: 0.2)) { store.update { $0.clearDone(in: listID) } }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove all completed TODOs from this list")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }

    private func emptyState(tint: Color, hasDone: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: hasDone ? "checkmark.seal.fill" : "tray")
                .font(.system(size: 26))
                .foregroundStyle(hasDone ? tint : Color.secondary.opacity(0.6))
            Text(hasDone ? "All done!" : "Nothing here yet")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Small colored dot used for lists.
struct ColorDot: View {
    let color: Color
    var size: CGFloat = 10
    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
    }
}
