import SwiftUI
import TodoCore

/// Contents of the edge drawer: the active list.
struct DrawerView: View {
    @ObservedObject var store: Store
    @ObservedObject var settings: AppSettings
    let openApp: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let list = store.data.activeList {
                header(list)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                TodoListContent(store: store, settings: settings, listID: list.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onExitCommand(perform: close)
    }

    private func header(_ list: TodoList) -> some View {
        HStack(spacing: 8) {
            Menu {
                Section("Show in edge bar") {
                    ForEach(store.data.lists) { other in
                        Button {
                            store.update { $0.setActive(other.id) }
                        } label: {
                            if other.id == list.id {
                                Label(other.name, systemImage: "checkmark")
                            } else {
                                Text(other.name)
                            }
                        }
                    }
                }
                Divider()
                Section("Text size") {
                    Button("Larger Text") { settings.biggerText() }
                    Button("Smaller Text") { settings.smallerText() }
                    Button("Default Size") { settings.resetText() }
                }
                Divider()
                Button("Manage Lists...", action: openApp)
            } label: {
                HStack(spacing: 7) {
                    ColorDot(color: list.color.color, size: 11)
                    Text(list.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Switch which list is shown here")

            Spacer(minLength: 4)

            Text("\(list.openItems.count) open")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button(action: openApp) {
                Image(systemName: "macwindow")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Sidebar Todos")
        }
    }
}
