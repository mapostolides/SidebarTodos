# Sidebar Todos

A running TODO list that lives on the left edge of your Mac screen.

- A slim tab sits on the left edge (with a count of open TODOs). Move the mouse
  onto it and the active list slides open; move away
  and it hides.
- Multiple lists; one "active" list is shown in the edge drawer. Switch it from
  the drawer header or the main window.
- Checked TODOs sink into a collapsible **Done** section (one-click Clear).
- Double-click to edit, drag to reorder, right-click to move between lists.
- Adjustable text size: type a point size in Settings, pick one from the drawer header menu, or use Cmd + / Cmd - / Cmd 0.
- Launches at login (toggle in Settings). Works over full-screen apps and all Spaces.
- Data: one JSON file at `~/Library/Application Support/SidebarTodos/todos.json`,
  saved on every change.

## Build and install

Needs macOS 14+ and the Swift toolchain (Xcode Command Line Tools are enough).

```bash
./scripts/build_app.sh --install   # builds and copies "Sidebar Todos.app" to /Applications
./scripts/test.sh                  # unit tests (swift-testing)
```
