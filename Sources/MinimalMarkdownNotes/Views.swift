import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var editorBridge: EditorBridge
    @State private var folderSheetMode: FolderSheetMode?
    @State private var noteSheetMode: NoteSheetMode?

    var body: some View {
        Group {
            if store.workspaceURL == nil {
                EmptyWorkspaceView()
            } else {
                NavigationSplitView {
                    SidebarView(folderSheetMode: $folderSheetMode, noteSheetMode: $noteSheetMode)
                        .navigationSplitViewColumnWidth(min: 280, ideal: 330)
                } detail: {
                    DetailView(noteSheetMode: $noteSheetMode)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.createNote()
                    editorBridge.requestFocus()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }

                Button {
                    folderSheetMode = .create(parentPath: store.selectedFolderPath)
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .disabled(store.workspaceURL == nil)

                Button {
                    store.chooseWorkspace()
                } label: {
                    Label("Choose Workspace", systemImage: "externaldrive")
                }
            }
        }
        .sheet(item: $folderSheetMode) { mode in
            FolderSheet(mode: mode)
                .environmentObject(store)
        }
        .sheet(item: $noteSheetMode) { mode in
            NoteSheet(mode: mode)
                .environmentObject(store)
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            ),
            actions: {
                Button("OK") {
                    store.errorMessage = nil
                }
            },
            message: {
                Text(store.errorMessage ?? "")
            }
        )
    }
}

private struct EmptyWorkspaceView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "note.text")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Node Taking")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Choose a local workspace folder to start writing and organizing Markdown notes.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
            }

            Button("Choose Workspace") {
                store.chooseWorkspace()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(red: 0.94, green: 0.97, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: VaultStore
    @Binding var folderSheetMode: FolderSheetMode?
    @Binding var noteSheetMode: NoteSheetMode?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Lens", selection: $store.selectedLens) {
                ForEach(Lens.allCases) { lens in
                    Label(lens.title, systemImage: lens.systemImage)
                        .tag(lens)
                }
            }
            .pickerStyle(.segmented)

            TextField("Search notes", text: $store.searchText)
                .textFieldStyle(.roundedBorder)

            switch store.selectedLens {
            case .hierarchy:
                HierarchyLensView(folderSheetMode: $folderSheetMode, noteSheetMode: $noteSheetMode)
            case .timeline:
                TimelineLensView()
            case .canvas:
                CanvasLensView()
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
}

private struct HierarchyLensView: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var editorBridge: EditorBridge
    @Binding var folderSheetMode: FolderSheetMode?
    @Binding var noteSheetMode: NoteSheetMode?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    store.createNote(in: store.selectedFolderPath)
                    editorBridge.requestFocus()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)

                Button {
                    folderSheetMode = .create(parentPath: store.selectedFolderPath)
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
            }

            List {
                OutlineGroup(store.hierarchyItems, children: \.children) { item in
                    switch item.kind {
                    case .folder:
                        FolderRow(folderSheetMode: $folderSheetMode, item: item)
                    case let .note(noteID):
                        NoteRow(noteID: noteID, noteSheetMode: $noteSheetMode)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct FolderRow: View {
    @EnvironmentObject private var store: VaultStore
    @Binding var folderSheetMode: FolderSheetMode?
    let item: HierarchyItem

    var isSelected: Bool {
        store.selectedFolderPath == item.relativePath && item.relativePath != store.selectedNote?.relativeFolderPath
    }

    var body: some View {
        Label(item.name, systemImage: "folder")
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .onTapGesture {
                store.selectedFolderPath = item.relativePath
            }
            .contextMenu {
                Button("New Note") {
                    store.createNote(in: item.relativePath)
                }
                Button("New Folder") {
                    folderSheetMode = .create(parentPath: item.relativePath)
                }
                if !item.relativePath.isEmpty {
                    Button("Rename Folder") {
                        folderSheetMode = .rename(path: item.relativePath)
                    }
                    Button("Delete Folder", role: .destructive) {
                        store.deleteFolder(at: item.relativePath)
                    }
                }
            }
    }
}

private struct NoteRow: View {
    @EnvironmentObject private var store: VaultStore
    let noteID: UUID
    @Binding var noteSheetMode: NoteSheetMode?

    var body: some View {
        if let note = store.notes.first(where: { $0.id == noteID }) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                    .font(.body)
                if !note.cleanedTags.isEmpty {
                    Text(note.cleanedTags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(store.selectedNoteID == note.id ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .onTapGesture {
                store.select(noteID: note.id)
            }
            .contextMenu {
                Button("Rename Note") {
                    store.select(noteID: note.id)
                    noteSheetMode = .rename(noteID: note.id, currentName: note.displayTitle)
                }
                Button("Duplicate Note") {
                    store.select(noteID: note.id)
                    store.duplicateSelectedNote()
                }
                Button("Delete Note", role: .destructive) {
                    store.delete(note: note)
                }
            }
        }
    }
}

private struct TimelineLensView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        if store.timelineSections.isEmpty {
            ContentUnavailableView("No Notes", systemImage: "clock")
        } else {
            List {
                ForEach(store.timelineSections) { section in
                    Section(section.title) {
                        ForEach(section.notes) { note in
                            TimelineNoteRow(note: note)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct TimelineNoteRow: View {
    @EnvironmentObject private var store: VaultStore
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.displayTitle)
            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            store.select(noteID: note.id)
        }
    }
}

private struct CanvasLensView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Zoom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $store.canvasZoom, in: 0.7...1.8)

                Menu("Filter Tags") {
                    if store.allTags.isEmpty {
                        Text("No tags yet")
                    } else {
                        ForEach(store.allTags, id: \.self) { tag in
                            Toggle(tag, isOn: Binding(
                                get: { store.selectedCanvasTags.contains(tag) },
                                set: { isOn in
                                    if isOn {
                                        store.selectedCanvasTags.insert(tag)
                                    } else {
                                        store.selectedCanvasTags.remove(tag)
                                    }
                                }
                            ))
                        }
                    }
                }
            }

            if store.canvasNotes.isEmpty {
                ContentUnavailableView("No Tagged Notes", systemImage: "square.grid.3x3")
            } else {
                ScrollView([.horizontal, .vertical]) {
                    TagCanvasView(notes: store.canvasNotes, zoom: store.canvasZoom)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            }
        }
    }
}

private struct TagCanvasView: View {
    @EnvironmentObject private var store: VaultStore
    let notes: [Note]
    let zoom: CGFloat

    private let baseSize = CGSize(width: 1200, height: 900)

    var body: some View {
        let layout = makeLayout()

        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for hub in layout.hubs {
                    let rect = CGRect(x: hub.position.x - 54, y: hub.position.y - 54, width: 108, height: 108)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color.accentColor.opacity(0.08))
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(Color.accentColor.opacity(0.24)),
                        lineWidth: 1
                    )
                }

                for positioned in layout.notes {
                    for point in positioned.connectedHubs {
                        var path = Path()
                        path.move(to: point)
                        path.addLine(to: positioned.position)
                        context.stroke(path, with: .color(Color.secondary.opacity(0.15)), lineWidth: 1)
                    }
                }
            }

            ForEach(layout.hubs, id: \.name) { hub in
                Text(hub.name)
                    .font(.system(.headline, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .position(hub.position)
            }

            ForEach(layout.notes, id: \.note.id) { positioned in
                Button {
                    store.select(noteID: positioned.note.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(positioned.note.displayTitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                        if !positioned.note.cleanedTags.isEmpty {
                            Text(positioned.note.cleanedTags.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(10)
                    .frame(width: 170, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(store.selectedNoteID == positioned.note.id ? Color.accentColor : Color.black.opacity(0.06), lineWidth: store.selectedNoteID == positioned.note.id ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .position(positioned.position)
                .accessibilityLabel(positioned.note.displayTitle)
            }
        }
        .frame(width: baseSize.width * zoom, height: baseSize.height * zoom)
    }

    private func makeLayout() -> CanvasLayout {
        let uniqueTags = notes.flatMap(\.cleanedTags).uniquedCaseInsensitive()
        let center = CGPoint(x: (baseSize.width * zoom) / 2, y: (baseSize.height * zoom) / 2)
        let radius = min(baseSize.width, baseSize.height) * 0.28 * zoom

        let hubs: [TagHub] = uniqueTags.enumerated().map { index, tag in
            let angle = (Double(index) / Double(max(uniqueTags.count, 1))) * (.pi * 2)
            let position = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            return TagHub(name: tag, position: position)
        }

        let hubLookup = Dictionary(uniqueKeysWithValues: hubs.map { ($0.name.lowercased(), $0.position) })

        let positionedNotes: [PositionedNote] = notes.enumerated().map { index, note in
            let tagPoints = note.cleanedTags.compactMap { hubLookup[$0.lowercased()] }
            let position: CGPoint
            if tagPoints.isEmpty {
                let column = index % 4
                let row = index / 4
                position = CGPoint(
                    x: center.x - 250 * zoom + CGFloat(column) * 180 * zoom,
                    y: center.y - 140 * zoom + CGFloat(row) * 120 * zoom
                )
            } else {
                let centroid = CGPoint(
                    x: tagPoints.map(\.x).reduce(0, +) / CGFloat(tagPoints.count),
                    y: tagPoints.map(\.y).reduce(0, +) / CGFloat(tagPoints.count)
                )
                let seed = abs(note.id.hashValue % 11)
                let offsetX = CGFloat((seed % 5) - 2) * 22 * zoom
                let offsetY = CGFloat((seed / 5) - 1) * 18 * zoom
                position = CGPoint(x: centroid.x + offsetX, y: centroid.y + offsetY)
            }
            return PositionedNote(note: note, position: position, connectedHubs: tagPoints)
        }

        return CanvasLayout(hubs: hubs, notes: positionedNotes)
    }
}

private struct DetailView: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var editorBridge: EditorBridge
    @Binding var noteSheetMode: NoteSheetMode?

    var body: some View {
        if let note = store.selectedNote {
            NoteEditorView(note: note, noteSheetMode: $noteSheetMode)
                .onAppear {
                    editorBridge.requestFocus()
                }
                .onChange(of: note.id) { _, _ in
                    editorBridge.requestFocus()
                }
        } else if store.workspaceURL != nil {
            ContentUnavailableView("No Note Selected", systemImage: "doc.text")
        }
    }
}

private struct NoteEditorView: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var editorBridge: EditorBridge
    let note: Note
    @Binding var noteSheetMode: NoteSheetMode?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    TextField("Title", text: store.noteBinding(note.id, keyPath: \.title))
                        .textFieldStyle(.plain)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))

                    Button {
                        noteSheetMode = .rename(noteID: note.id, currentName: note.displayTitle)
                    } label: {
                        Label("Rename Note", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Rename Note")
                }

                HStack(spacing: 14) {
                    Label(note.relativeFolderPath.isEmpty ? "/" : note.relativeFolderPath, systemImage: "folder")
                    Label(note.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                TagEditorView(note: note)
            }

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FormatAction.allCases) { action in
                        Button {
                            editorBridge.apply(action)
                        } label: {
                            Label(action.label, systemImage: action.symbol)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            MarkdownEditorView(text: store.noteBinding(note.id, keyPath: \.markdownBody), bridge: editorBridge)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
        }
        .padding(24)
    }
}

private struct TagEditorView: View {
    @EnvironmentObject private var store: VaultStore
    let note: Note
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(note.cleanedTags, id: \.self) { tag in
                        HStack(spacing: 6) {
                            Text(tag)
                            Button {
                                store.updateTags(for: note.id, tags: note.cleanedTags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame })
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12))
                        )
                    }
                }
            }

            TextField("Add tags", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    commitDraft()
                }

            let suggestions = store.tagSuggestions(for: draft, excluding: note.cleanedTags)
            if !suggestions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(suggestions.prefix(6), id: \.self) { suggestion in
                        Button(suggestion) {
                            add(tag: suggestion)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func commitDraft() {
        let pieces = draft
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !pieces.isEmpty else { return }
        let next = (note.cleanedTags + pieces)
            .uniquedCaseInsensitive()
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        store.updateTags(for: note.id, tags: next)
        draft = ""
    }

    private func add(tag: String) {
        let next = (note.cleanedTags + [tag])
            .uniquedCaseInsensitive()
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        store.updateTags(for: note.id, tags: next)
        draft = ""
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        Form {
            Picker("Language", selection: $store.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }

            HStack {
                Text("Workspace")
                Spacer()
                Text(store.workspaceURL?.path ?? "Not selected")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Button("Choose Workspace") {
                    store.chooseWorkspace()
                }

                Button("Import Notes…") {
                    store.importNotes()
                }

                Button("Export Visible Notes…") {
                    store.exportAllNotes()
                }
                .disabled(store.filteredNotes.isEmpty)
            }

            Text("Language changes may require restarting the app on some macOS versions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 620)
    }
}

private struct FolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: VaultStore
    let mode: FolderSheetMode
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.title3.weight(.semibold))

            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    name = mode.defaultName
                }
                .onSubmit {
                    submit()
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(mode.confirmationTitle) {
                    submit()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func submit() {
        switch mode {
        case let .create(parentPath):
            store.createFolder(named: name, parentPath: parentPath)
        case let .rename(path):
            store.renameFolder(at: path, to: name)
        }
        dismiss()
    }
}

private struct NoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: VaultStore
    let mode: NoteSheetMode
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.title3.weight(.semibold))

            TextField("Note name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    name = mode.defaultName
                }
                .onSubmit {
                    submit()
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(mode.confirmationTitle) {
                    submit()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func submit() {
        switch mode {
        case let .rename(noteID, _):
            store.renameNote(noteID: noteID, to: name)
        }
        dismiss()
    }
}

private enum FolderSheetMode: Identifiable {
    case create(parentPath: String)
    case rename(path: String)

    var id: String {
        switch self {
        case let .create(parentPath):
            "create-\(parentPath)"
        case let .rename(path):
            "rename-\(path)"
        }
    }

    var title: String {
        switch self {
        case .create:
            "New Folder"
        case .rename:
            "Rename Folder"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .create:
            "Create"
        case .rename:
            "Rename"
        }
    }

    var defaultName: String {
        switch self {
        case .create:
            ""
        case let .rename(path):
            URL(fileURLWithPath: path).lastPathComponent
        }
    }
}

private enum NoteSheetMode: Identifiable {
    case rename(noteID: UUID, currentName: String)

    var id: String {
        switch self {
        case let .rename(noteID, _):
            "rename-note-\(noteID.uuidString)"
        }
    }

    var title: String {
        "Rename Note"
    }

    var confirmationTitle: String {
        "Rename"
    }

    var defaultName: String {
        switch self {
        case let .rename(_, currentName):
            currentName
        }
    }
}

private struct TagHub {
    let name: String
    let position: CGPoint
}

private struct PositionedNote {
    let note: Note
    let position: CGPoint
    let connectedHubs: [CGPoint]
}

private struct CanvasLayout {
    let hubs: [TagHub]
    let notes: [PositionedNote]
}
