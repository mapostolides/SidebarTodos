import SwiftUI
import TodoCore

final class MainSelection: ObservableObject {
    @Published var listID: UUID?
    @Published var renameRequest: UUID?
}

/// The main window: all lists on the left, the selected list on the right.
struct MainView: View {
    @ObservedObject var store: Store
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: MainSelection
    @State private var pendingDelete: TodoList?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
        } detail: {
            if let id = selection.listID, store.list(id) != nil {
                ListDetailView(store: store, settings: settings, selection: selection, listID: id)
                    .id(id)
            } else {
                Text("Select a list")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .onAppear(perform: ensureSelection)
        .onChange(of: store.data.lists.map(\.id)) { _, _ in ensureSelection() }
        .confirmationDialog(
            "Delete \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { list in
            Button("Delete List and \(list.items.count) TODOs", role: .destructive) {
                store.update { _ = $0.deleteList(list.id) }
            }
        } message: { _ in
            Text("This cannot be undone.")
        }
    }

    private func ensureSelection() {
        if selection.listID == nil || store.list(selection.listID!) == nil {
            selection.listID = store.data.activeList?.id
        }
    }

    private var sidebar: some View {
        List(selection: $selection.listID) {
            Section("Lists") {
                ForEach(store.data.lists) { list in
                    let isActive = list.id == store.data.activeList?.id
                    HStack(spacing: 8) {
                        ColorDot(color: list.color.color)
                        Text(list.name).lineLimit(1)
                        Spacer(minLength: 4)
                        if isActive {
                            Image(systemName: "sidebar.left")
                                .font(.caption)
                                .foregroundStyle(list.color.color)
                                .help("Shown in the edge bar")
                        }
                        let open = list.openItems.count
                        if open > 0 {
                            Text("\(open)")
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(list.id)
                    .contextMenu {
                        Button("Show in Edge Bar") { store.update { $0.setActive(list.id) } }
                            .disabled(isActive)
                        Button("Rename") {
                            selection.listID = list.id
                            selection.renameRequest = list.id
                        }
                        Menu("Color") { colorButtons(for: list) }
                        Divider()
                        Button("Delete List...", role: .destructive) { pendingDelete = list }
                            .disabled(store.data.lists.count <= 1)
                    }
                }
                .onMove { from, to in store.update { $0.moveLists(from: from, to: to) } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                newList()
            } label: {
                Label("New List", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func colorButtons(for list: TodoList) -> some View {
        ForEach(ListColor.allCases, id: \.self) { c in
            Button {
                store.update { $0.setColor(c, for: list.id) }
            } label: {
                if c == list.color { Label(c.label, systemImage: "checkmark") } else { Text(c.label) }
            }
        }
    }

    func newList() {
        var newID: UUID?
        store.update { newID = $0.addList(name: "New List") }
        selection.listID = newID
        selection.renameRequest = newID
    }
}

struct ListDetailView: View {
    @ObservedObject var store: Store
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: MainSelection
    let listID: UUID
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        if let list = store.list(listID) {
            let isActive = list.id == store.data.activeList?.id
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(ListColor.allCases, id: \.self) { c in
                            Button {
                                store.update { $0.setColor(c, for: listID) }
                            } label: {
                                Label(c.label, systemImage: c == list.color ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                    } label: {
                        ColorDot(color: list.color.color, size: 16)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("List color")

                    TextField("List name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 24, weight: .bold))
                        .focused($nameFocused)
                        .onSubmit(saveName)
                        .onChange(of: nameFocused) { _, f in if !f { saveName() } }

                    Spacer()

                    if isActive {
                        Label("In edge bar", systemImage: "sidebar.left")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(list.color.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(list.color.color.opacity(0.14)))
                            .help("This list is shown in the edge bar on the left of your screen")
                    } else {
                        Button {
                            store.update { $0.setActive(listID) }
                        } label: {
                            Label("Show in Edge Bar", systemImage: "sidebar.left")
                        }
                        .controlSize(.regular)
                        .help("Make this the list shown in the edge bar")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Text("\(list.openItems.count) open, \(list.doneItems.count) done")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 22)
                    .padding(.top, -8)

                TodoListContent(store: store, settings: settings, listID: listID, large: true)
            }
            .onAppear {
                name = list.name
                if selection.renameRequest == listID {
                    selection.renameRequest = nil
                    DispatchQueue.main.async { nameFocused = true }
                }
            }
            .onChange(of: selection.renameRequest) { _, req in
                if req == listID {
                    selection.renameRequest = nil
                    nameFocused = true
                }
            }
            .onChange(of: list.name) { _, n in if !nameFocused { name = n } }
        }
    }

    private func saveName() {
        store.update { $0.renameList(listID, to: name) }
        name = store.list(listID)?.name ?? name
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let dataURL: URL
    @State private var screens: [(id: UInt32, name: String)] = []

    var body: some View {
        Form {
            Section {
                Toggle("Open Sidebar Todos when you log in", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if let note = settings.loginNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Show the edge tab on", selection: $settings.displayID) {
                    Text("Main display").tag(UInt32(0))
                    ForEach(screens, id: \.id) { s in Text(s.name).tag(s.id) }
                }
                LabeledContent("TODO text size") {
                    HStack(spacing: 8) {
                        Text("A").font(.system(size: 10))
                        Slider(value: $settings.fontSize, in: AppSettings.fontSizeRange, step: 1)
                            .frame(width: 160)
                        Text("A").font(.system(size: 18))
                        Text("\(Int(settings.fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Picker("Add new TODOs at the", selection: $settings.newItemsAtTop) {
                    Text("Top").tag(true)
                    Text("Bottom").tag(false)
                }
            }
            Section("Data") {
                LabeledContent("Saved to") {
                    Text(dataURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([dataURL])
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            settings.refreshLoginStatus()
            screens = NSScreen.screens.map { ($0.displayID, $0.localizedName) }
        }
    }
}
