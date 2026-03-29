import AppKit
import Foundation
import SwiftUI

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var workspaceURL: URL?
    @Published private(set) var notes: [Note] = []
    @Published private(set) var folderPaths: Set<String> = [""]
    @Published var selectedNoteID: UUID?
    @Published var selectedLens: Lens = .hierarchy
    @Published var selectedFolderPath = ""
    @Published var searchText = ""
    @Published var selectedCanvasTags = Set<String>()
    @Published var canvasZoom: CGFloat = 1.0
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
        }
    }
    @Published var errorMessage: String?

    private static let bookmarkKey = "workspaceBookmark"
    private static let languageKey = "preferredLanguage"

    private let fileManager = FileManager.default
    private var autosaveTasks: [UUID: Task<Void, Never>] = [:]
    private var securityScopedURL: URL?

    init() {
        language = Self.loadSavedLanguage()
    }

    var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return notes.first(where: { $0.id == selectedNoteID })
    }

    var workspaceDisplayName: String {
        workspaceURL?.lastPathComponent ?? "Workspace"
    }

    var filteredNotes: [Note] {
        notes
            .filter(matchesSearch)
            .sorted(by: noteSort)
    }

    var allTags: [String] {
        notes
            .flatMap(\.tags)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedCaseInsensitive()
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var hierarchyItems: [HierarchyItem] {
        guard workspaceURL != nil else { return [] }
        return [buildFolderNode(for: "")]
    }

    var timelineSections: [TimelineSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let buckets: [(String, (Date) -> Bool)] = [
            ("Today", { calendar.isDate($0, inSameDayAs: today) }),
            ("Yesterday", { calendar.isDate($0, inSameDayAs: yesterday) }),
            ("This Week", { calendar.isDate($0, equalTo: Date(), toGranularity: .weekOfYear) && !calendar.isDate($0, inSameDayAs: today) && !calendar.isDate($0, inSameDayAs: yesterday) }),
            ("This Month", { calendar.isDate($0, equalTo: Date(), toGranularity: .month) && !calendar.isDate($0, equalTo: Date(), toGranularity: .weekOfYear) }),
            ("Older", { _ in true }),
        ]

        var consumed = Set<UUID>()
        var sections: [TimelineSection] = []

        for bucket in buckets {
            let bucketNotes = filteredNotes
                .filter { !consumed.contains($0.id) && bucket.1($0.createdAt) }
                .sorted { $0.createdAt > $1.createdAt }
            guard !bucketNotes.isEmpty else { continue }
            consumed.formUnion(bucketNotes.map(\.id))
            sections.append(TimelineSection(id: bucket.0, title: bucket.0, notes: bucketNotes))
        }

        return sections
    }

    var canvasNotes: [Note] {
        let base = filteredNotes
        guard !selectedCanvasTags.isEmpty else { return base }
        return base.filter { note in
            !selectedCanvasTags.isDisjoint(with: Set(note.cleanedTags))
        }
    }

    func bootstrap() {
        guard workspaceURL == nil else { return }
        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            openWorkspace(url: url, persistBookmark: isStale)
        } catch {
            errorMessage = "Could not restore the previous workspace: \(error.localizedDescription)"
        }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.prompt = "Open Workspace"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWorkspace(url: url, persistBookmark: true)
    }

    func createNote(in folderPath: String? = nil) {
        guard workspaceURL != nil else { return }
        let parentFolder = normalizedFolderPath(folderPath ?? activeFolderPath)
        let id = UUID()
        let now = Date()
        let title = "Untitled"
        let fileNameStem = availableFileNameStem(for: title, in: parentFolder, excluding: nil)
        let note = Note(
            id: id,
            title: title,
            markdownBody: "",
            createdAt: now,
            updatedAt: now,
            tags: [],
            relativeFolderPath: parentFolder,
            fileNameStem: fileNameStem,
            originalImportedID: nil
        )

        notes.append(note)
        folderPaths.insert(parentFolder)
        select(noteID: note.id)
        scheduleSave(note: note, previous: nil, delayNanoseconds: 0)
    }

    func duplicateSelectedNote() {
        guard let note = selectedNote else { return }
        let now = Date()
        let duplicated = Note(
            id: UUID(),
            title: "\(note.displayTitle) Copy",
            markdownBody: note.markdownBody,
            createdAt: now,
            updatedAt: now,
            tags: note.cleanedTags,
            relativeFolderPath: note.relativeFolderPath,
            fileNameStem: availableFileNameStem(for: "\(note.displayTitle)-copy", in: note.relativeFolderPath, excluding: nil),
            originalImportedID: note.originalImportedID
        )
        notes.append(duplicated)
        select(noteID: duplicated.id)
        scheduleSave(note: duplicated, previous: nil, delayNanoseconds: 0)
    }

    func deleteSelectedNote() {
        guard let note = selectedNote else { return }
        delete(note: note)
    }

    func delete(note: Note) {
        autosaveTasks[note.id]?.cancel()
        do {
            try trashItem(at: noteFileURL(for: note))
            try trashItem(at: metadataURL(for: note))
        } catch {
            errorMessage = "Could not delete note: \(error.localizedDescription)"
        }
        notes.removeAll { $0.id == note.id }
        if selectedNoteID == note.id {
            selectedNoteID = notes.sorted(by: noteSort).first?.id
        }
    }

    func createFolder(named name: String, parentPath: String? = nil) {
        guard let workspaceURL else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let parent = normalizedFolderPath(parentPath ?? activeFolderPath)
        let newPath = normalizedFolderPath([parent, trimmed].filter { !$0.isEmpty }.joined(separator: "/"))
        let url = workspaceURL.appendingPathComponent(newPath, isDirectory: true)

        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            reloadWorkspace()
            selectedFolderPath = newPath
        } catch {
            errorMessage = "Could not create folder: \(error.localizedDescription)"
        }
    }

    func renameFolder(at folderPath: String, to newName: String) {
        guard let workspaceURL, !folderPath.isEmpty else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let originalURL = workspaceURL.appendingPathComponent(folderPath, isDirectory: true)
        let parentPath = normalizedFolderPath((folderPath as NSString).deletingLastPathComponent)
        let destinationPath = normalizedFolderPath([parentPath, trimmed].filter { !$0.isEmpty }.joined(separator: "/"))
        let destinationURL = workspaceURL.appendingPathComponent(destinationPath, isDirectory: true)

        do {
            try fileManager.moveItem(at: originalURL, to: destinationURL)
            for index in notes.indices {
                guard notes[index].relativeFolderPath == folderPath || notes[index].relativeFolderPath.hasPrefix(folderPath + "/") else { continue }
                notes[index].relativeFolderPath = notes[index].relativeFolderPath.replacingOccurrences(of: folderPath, with: destinationPath, options: [.anchored])
                scheduleSave(note: notes[index], previous: nil, delayNanoseconds: 0)
            }
            reloadWorkspace()
            selectedFolderPath = destinationPath
        } catch {
            errorMessage = "Could not rename folder: \(error.localizedDescription)"
        }
    }

    func deleteFolder(at folderPath: String) {
        guard let workspaceURL, !folderPath.isEmpty else { return }
        do {
            try trashItem(at: workspaceURL.appendingPathComponent(folderPath, isDirectory: true))
            reloadWorkspace()
            selectedFolderPath = ""
        } catch {
            errorMessage = "Could not delete folder: \(error.localizedDescription)"
        }
    }

    func updateTitle(for noteID: UUID, title: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let previous = notes[index]
        notes[index].title = title
        notes[index].updatedAt = Date()
        scheduleSave(note: notes[index], previous: previous)
    }

    func updateBody(for noteID: UUID, body: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let previous = notes[index]
        notes[index].markdownBody = body
        notes[index].updatedAt = Date()
        scheduleSave(note: notes[index], previous: previous)
    }

    func updateTags(for noteID: UUID, tags: [String]) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let previous = notes[index]
        notes[index].tags = tags
        notes[index].updatedAt = Date()
        scheduleSave(note: notes[index], previous: previous)
    }

    func select(noteID: UUID) {
        selectedNoteID = noteID
        if let note = notes.first(where: { $0.id == noteID }) {
            selectedFolderPath = note.relativeFolderPath
        }
    }

    func exportAllNotes() {
        export(notes: filteredNotes)
    }

    func exportSelectedNote() {
        guard let selectedNote else { return }
        export(notes: [selectedNote])
    }

    func importNotes() {
        let panel = NSOpenPanel()
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(NotesExportEnvelope.self, from: data)
            ingestImportedNotes(envelope.notes)
        } catch {
            errorMessage = "Could not import notes: \(error.localizedDescription)"
        }
    }

    func noteBinding(_ noteID: UUID, keyPath: WritableKeyPath<Note, String>) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.notes.first(where: { $0.id == noteID })?[keyPath: keyPath] ?? ""
            },
            set: { [weak self] value in
                if keyPath == \Note.title {
                    self?.updateTitle(for: noteID, title: value)
                } else if keyPath == \Note.markdownBody {
                    self?.updateBody(for: noteID, body: value)
                }
            }
        )
    }

    func tagSuggestions(for partial: String, excluding tags: [String]) -> [String] {
        let needle = partial.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let excluded = Set(tags.map { $0.lowercased() })
        return allTags.filter {
            $0.lowercased().contains(needle) && !excluded.contains($0.lowercased())
        }
    }

    private func openWorkspace(url: URL, persistBookmark: Bool) {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        securityScopedURL = url
        workspaceURL = url
        selectedFolderPath = ""

        if persistBookmark {
            do {
                let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            } catch {
                errorMessage = "Workspace opened, but access could not be persisted: \(error.localizedDescription)"
            }
        }

        reloadWorkspace()
    }

    private func reloadWorkspace() {
        guard let workspaceURL else {
            notes = []
            folderPaths = [""]
            selectedNoteID = nil
            return
        }

        var loadedNotes: [Note] = []
        var discoveredFolders: Set<String> = [""]

        guard let enumerator = fileManager.enumerator(
            at: workspaceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            notes = []
            folderPaths = [""]
            return
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                discoveredFolders.insert(relativePath(of: url, relativeTo: workspaceURL))
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }
            do {
                loadedNotes.append(try loadNote(at: url, workspaceURL: workspaceURL))
                discoveredFolders.insert(relativePath(of: url.deletingLastPathComponent(), relativeTo: workspaceURL))
            } catch {
                errorMessage = "Could not load \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        notes = loadedNotes.sorted(by: noteSort)
        folderPaths = discoveredFolders

        if let selectedNoteID, notes.contains(where: { $0.id == selectedNoteID }) {
            selectedFolderPath = selectedNote?.relativeFolderPath ?? ""
        } else {
            selectedNoteID = notes.first?.id
        }
    }

    private func loadNote(at url: URL, workspaceURL: URL) throws -> Note {
        let markdownBody = try String(contentsOf: url, encoding: .utf8)
        let metadataURL = url.deletingPathExtension().appendingPathExtension("meta.json")

        let fileValues = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let createdAt = fileValues.creationDate ?? Date()
        let updatedAt = fileValues.contentModificationDate ?? createdAt
        let relativeFolderPath = relativePath(of: url.deletingLastPathComponent(), relativeTo: workspaceURL)
        let fileNameStem = url.deletingPathExtension().lastPathComponent

        if fileManager.fileExists(atPath: metadataURL.path) {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metadata = try decoder.decode(NoteMetadata.self, from: data)

            return Note(
                id: metadata.id,
                title: metadata.title,
                markdownBody: markdownBody,
                createdAt: metadata.createdAt,
                updatedAt: metadata.updatedAt,
                tags: metadata.tags,
                relativeFolderPath: normalizedFolderPath(metadata.relativeFolderPath),
                fileNameStem: metadata.fileNameStem,
                originalImportedID: metadata.originalImportedID
            )
        }

        return Note(
            id: UUID(),
            title: fileNameStem,
            markdownBody: markdownBody,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tags: [],
            relativeFolderPath: relativeFolderPath,
            fileNameStem: fileNameStem,
            originalImportedID: nil
        )
    }

    private func export(notes exportedNotes: [Note]) {
        guard !exportedNotes.isEmpty else { return }

        let panel = NSSavePanel()
        panel.prompt = "Export"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = exportedNotes.count == 1 ? "\(exportedNotes[0].displayTitle).json" : "Markdown Notes Export.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let envelope = NotesExportEnvelope(schemaVersion: 1, exportedAt: Date(), notes: exportedNotes.map(\.exported))
            let data = try encoder.encode(envelope)
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = "Could not export notes: \(error.localizedDescription)"
        }
    }

    private func ingestImportedNotes(_ exportedNotes: [ExportedNote]) {
        guard workspaceURL != nil else { return }
        let existingIDs = Set(notes.map(\.id))
        var importedSelection: UUID?

        for exportedNote in exportedNotes {
            let resolvedID = existingIDs.contains(exportedNote.id) ? UUID() : exportedNote.id
            let note = Note(
                id: resolvedID,
                title: exportedNote.title,
                markdownBody: exportedNote.markdownBody,
                createdAt: exportedNote.createdAt,
                updatedAt: exportedNote.updatedAt,
                tags: exportedNote.tags,
                relativeFolderPath: normalizedFolderPath(exportedNote.relativePath),
                fileNameStem: availableFileNameStem(for: exportedNote.title, in: normalizedFolderPath(exportedNote.relativePath), excluding: nil),
                originalImportedID: existingIDs.contains(exportedNote.id) ? exportedNote.id : nil
            )
            notes.append(note)
            folderPaths.insert(note.relativeFolderPath)
            scheduleSave(note: note, previous: nil, delayNanoseconds: 0)
            importedSelection = note.id
        }

        notes.sort(by: noteSort)
        if let importedSelection {
            select(noteID: importedSelection)
        }
    }

    private func scheduleSave(note: Note, previous: Note?, delayNanoseconds: UInt64 = 450_000_000) {
        autosaveTasks[note.id]?.cancel()
        autosaveTasks[note.id] = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.persist(note: note, previous: previous)
            }
        }
    }

    private func persist(note: Note, previous: Note?) {
        guard let workspaceURL else { return }

        do {
            let directoryURL = workspaceURL.appendingPathComponent(note.relativeFolderPath, isDirectory: true)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if let previous, previous.id == note.id, previous.fileNameStem != note.fileNameStem || previous.relativeFolderPath != note.relativeFolderPath {
                let previousNoteURL = noteFileURL(for: previous)
                let previousMetadataURL = metadataURL(for: previous)
                if fileManager.fileExists(atPath: previousNoteURL.path) {
                    try? fileManager.moveItem(at: previousNoteURL, to: noteFileURL(for: note))
                }
                if fileManager.fileExists(atPath: previousMetadataURL.path) {
                    try? fileManager.moveItem(at: previousMetadataURL, to: metadataURL(for: note))
                }
            }

            try coordinateWrite(data: Data(note.markdownBody.utf8), to: noteFileURL(for: note))

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let metadataData = try encoder.encode(note.metadata)
            try coordinateWrite(data: metadataData, to: metadataURL(for: note))
        } catch {
            errorMessage = "Could not save \(note.displayTitle): \(error.localizedDescription)"
        }
    }

    private func coordinateWrite(data: Data, to url: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }

    private func buildFolderNode(for path: String) -> HierarchyItem {
        let visibleNotes = filteredNotes.filter { $0.relativeFolderPath == path }
        let childPaths = folderPaths
            .filter { $0 != path && parentPath(of: $0) == path }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .filter { folderContainsVisibleContent($0) || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var children = childPaths.map(buildFolderNode(for:))
        children.append(contentsOf: visibleNotes.map { note in
            HierarchyItem(
                id: "note-\(note.id.uuidString)",
                name: note.displayTitle,
                kind: .note(note.id),
                relativePath: note.relativeFolderPath,
                children: nil
            )
        })

        children.sort { lhs, rhs in
            switch (lhs.kind, rhs.kind) {
            case (.folder, .note):
                true
            case (.note, .folder):
                false
            default:
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

        return HierarchyItem(
            id: path.isEmpty ? "folder-root" : "folder-\(path)",
            name: path.isEmpty ? workspaceDisplayName : URL(fileURLWithPath: path).lastPathComponent,
            kind: .folder,
            relativePath: path,
            children: children
        )
    }

    private func folderContainsVisibleContent(_ path: String) -> Bool {
        if filteredNotes.contains(where: { $0.relativeFolderPath == path }) {
            return true
        }
        return folderPaths.contains { candidate in
            candidate != path && parentPath(of: candidate) == path && folderContainsVisibleContent(candidate)
        }
    }

    private var activeFolderPath: String {
        if !selectedFolderPath.isEmpty || folderPaths.contains(selectedFolderPath) {
            return selectedFolderPath
        }
        return selectedNote?.relativeFolderPath ?? ""
    }

    private func availableFileNameStem(for title: String, in folderPath: String, excluding noteID: UUID?) -> String {
        let base = slugify(title)
        var candidate = base
        var counter = 2

        while notes.contains(where: {
            $0.relativeFolderPath == folderPath &&
            $0.fileNameStem == candidate &&
            $0.id != noteID
        }) {
            candidate = "\(base)-\(counter)"
            counter += 1
        }

        return candidate
    }

    private func noteFileURL(for note: Note) -> URL {
        guard let workspaceURL else { return URL(fileURLWithPath: "/") }
        let directory = workspaceURL.appendingPathComponent(note.relativeFolderPath, isDirectory: true)
        return directory.appendingPathComponent(note.fileNameStem).appendingPathExtension("md")
    }

    private func metadataURL(for note: Note) -> URL {
        noteFileURL(for: note).deletingPathExtension().appendingPathExtension("meta.json")
    }

    private func trashItem(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        var resultURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultURL)
    }

    private func matchesSearch(_ note: Note) -> Bool {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return note.displayTitle.lowercased().contains(needle)
            || note.markdownBody.lowercased().contains(needle)
            || note.cleanedTags.joined(separator: " ").lowercased().contains(needle)
    }

    private func noteSort(lhs: Note, rhs: Note) -> Bool {
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func relativePath(of url: URL, relativeTo root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        guard fullPath.hasPrefix(rootPath) else { return "" }
        let suffix = fullPath.dropFirst(rootPath.count)
        return normalizedFolderPath(String(suffix))
    }

    private func parentPath(of path: String) -> String {
        let normalized = normalizedFolderPath(path)
        guard !normalized.isEmpty else { return "" }
        let parent = (normalized as NSString).deletingLastPathComponent
        return parent == "." ? "" : normalizedFolderPath(parent)
    }

    private func normalizedFolderPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    private func slugify(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return cleaned.isEmpty ? "note-\(UUID().uuidString.prefix(8))" : cleaned
    }

    private static func loadSavedLanguage() -> AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: languageKey), let language = AppLanguage(rawValue: raw) else {
            return .system
        }
        return language
    }
}
