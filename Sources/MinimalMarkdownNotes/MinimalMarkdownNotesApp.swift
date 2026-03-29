import SwiftUI

@main
struct NodeTakingApp: App {
    @StateObject private var store = VaultStore()
    @StateObject private var editorBridge = EditorBridge()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(editorBridge)
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    store.bootstrap()
                }
        }
        .commands {
            SidebarCommands()
            TextEditingCommands()
            NoteCommands(store: store, editorBridge: editorBridge)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

struct NoteCommands: Commands {
    @ObservedObject var store: VaultStore
    @ObservedObject var editorBridge: EditorBridge

    var body: some Commands {
        CommandMenu("Notes") {
            Button("New Note") {
                store.createNote()
                editorBridge.requestFocus()
            }
            .keyboardShortcut("n")

            Button("Duplicate Note") {
                store.duplicateSelectedNote()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(store.selectedNote == nil)

            Button("Delete Note") {
                store.deleteSelectedNote()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(store.selectedNote == nil)

            Divider()

            Button("Import Notes…") {
                store.importNotes()
            }

            Button("Export Selected Note…") {
                store.exportSelectedNote()
            }
            .disabled(store.selectedNote == nil)

            Button("Export Visible Notes…") {
                store.exportAllNotes()
            }
            .disabled(store.filteredNotes.isEmpty)
        }

        CommandMenu("Format") {
            ForEach(FormatAction.allCases) { action in
                Button(action.label) {
                    editorBridge.apply(action)
                }
                .disabled(store.selectedNote == nil)
            }
        }
    }
}
