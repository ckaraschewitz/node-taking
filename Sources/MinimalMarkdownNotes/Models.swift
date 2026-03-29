import Foundation

enum Lens: String, CaseIterable, Identifiable {
    case hierarchy
    case timeline
    case canvas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hierarchy: "Folders"
        case .timeline: "Timeline"
        case .canvas: "Canvas"
        }
    }

    var systemImage: String {
        switch self {
        case .hierarchy: "folder"
        case .timeline: "clock"
        case .canvas: "square.grid.3x3.topleft.filled"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case english
    case german

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .german: "German"
        }
    }
}

enum FormatAction: CaseIterable, Identifiable {
    case bold
    case italic
    case h1
    case h2
    case h3
    case bulletList
    case numberedList
    case blockquote
    case codeBlock

    var id: String { label }

    var label: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .h1: "H1"
        case .h2: "H2"
        case .h3: "H3"
        case .bulletList: "Bullets"
        case .numberedList: "Numbers"
        case .blockquote: "Quote"
        case .codeBlock: "Code"
        }
    }

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .h1: "textformat.size.larger"
        case .h2: "textformat.size"
        case .h3: "textformat.size.smaller"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .blockquote: "text.quote"
        case .codeBlock: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct Note: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var markdownBody: String
    var createdAt: Date
    var updatedAt: Date
    var tags: [String]
    var relativeFolderPath: String
    var fileNameStem: String
    var originalImportedID: UUID?
}

struct NoteMetadata: Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var tags: [String]
    var relativeFolderPath: String
    var fileNameStem: String
    var originalImportedID: UUID?
}

struct NotesExportEnvelope: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var notes: [ExportedNote]
}

struct ExportedNote: Codable {
    var id: UUID
    var title: String
    var markdownBody: String
    var createdAt: Date
    var updatedAt: Date
    var tags: [String]
    var relativePath: String
}

struct HierarchyItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case folder
        case note(UUID)
    }

    let id: String
    let name: String
    let kind: Kind
    let relativePath: String
    var children: [HierarchyItem]?
}

struct TimelineSection: Identifiable {
    let id: String
    let title: String
    let notes: [Note]
}

extension Note {
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title
    }

    var cleanedTags: [String] {
        tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedCaseInsensitive()
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var metadata: NoteMetadata {
        NoteMetadata(
            id: id,
            title: displayTitle,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tags: cleanedTags,
            relativeFolderPath: relativeFolderPath,
            fileNameStem: fileNameStem,
            originalImportedID: originalImportedID
        )
    }

    var exported: ExportedNote {
        ExportedNote(
            id: id,
            title: displayTitle,
            markdownBody: markdownBody,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tags: cleanedTags,
            relativePath: relativeFolderPath
        )
    }
}

extension Array where Element == String {
    func uniquedCaseInsensitive() -> [String] {
        var seen = Set<String>()
        return filter { value in
            let key = value.lowercased()
            return seen.insert(key).inserted
        }
    }
}
