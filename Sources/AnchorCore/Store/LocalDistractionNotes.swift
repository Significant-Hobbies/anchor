import Foundation
import SwiftData

/// Local files adjacent to the local database, explicitly excluded from backup.
/// No CloudKit configuration, relationship, network transport or account identity.
struct LocalDistractionNotes {
    struct Content: Codable, Equatable {
        var note: String
        var keywords: [String]
    }
    struct Record: Codable, Equatable {
        var current: Content
        var legacyAlternates: [Content] = []
    }
    let directory: URL

    init(storeURL: URL) {
        directory = storeURL.appendingPathExtension("private-notes")
    }

    func read(_ id: UUID) throws -> Record? {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
    }

    func write(_ record: Record, id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        guard try read(id) == record else { throw CocoaError(.fileWriteUnknown) }
    }

    func delete(_ id: UUID) throws {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func preserveLegacy(_ content: Content, id: UUID) throws {
        var record = try read(id) ?? Record(current: content)
        if record.current != content && !record.legacyAlternates.contains(content) {
            record.legacyAlternates.append(content)
        }
        try write(record, id: id)
    }
}

extension ModelContext {
    var localDistractionNotes: LocalDistractionNotes? {
        guard let config = container.configurations.first, !config.isStoredInMemoryOnly else { return nil }
        return LocalDistractionNotes(storeURL: config.url)
    }
}

extension Distraction {
    @MainActor public func updatePrivateNote(_ text: String, in context: ModelContext) throws {
        let originalDraft = privateDraft
        privateNote = text
        do { try persistPrivateContent(in: context) }
        catch {
            privateDraft = originalDraft
            throw error
        }
    }

    public var retainedLegacyNotes: [String] {
        guard let context = modelContext, let vault = context.localDistractionNotes,
              let record = try? vault.read(id) else { return [] }
        return record.legacyAlternates.map(\.note)
    }

    /// Persist new/edited local content before the shared model can be saved.
    @MainActor public func persistPrivateContent(in context: ModelContext) throws {
        guard let vault = context.localDistractionNotes else {
            // In-memory preview/test stores never mirror or write to disk.
            if let privateDraft {
                note = privateDraft.note
                keywords = privateDraft.keywords
            }
            return
        }
        do {
            _ = try vault.read(id) // Corruption is not an absent note.
            if let draft = privateDraft {
                var record = try vault.read(id) ?? .init(current: draft)
                record.current = draft
                try vault.write(record, id: id)
                privateDraft = nil
            } else if !note.isEmpty || !keywords.isEmpty {
                try vault.preserveLegacy(.init(note: note, keywords: keywords), id: id)
            }
        }
        note = ""
        keywords = []
    }
}

extension AnchorStore {
    @MainActor public static func deleteDistraction(_ distraction: Distraction, in context: ModelContext) throws {
        let id = distraction.id
        let vault = context.localDistractionNotes
        context.delete(distraction)
        try context.save()
        // Keep the note recoverable if metadata deletion fails. A local cleanup
        // error is reported rather than silently claiming complete deletion.
        try vault?.delete(id)
    }

    /// Caller must open a local-only container for this phase. Copy and verify
    /// first; a failed copy leaves the corresponding source fields untouched.
    @MainActor static func migratePrivateNotes(in context: ModelContext) throws {
        for distraction in try context.fetch(FetchDescriptor<Distraction>()) {
            try distraction.persistPrivateContent(in: context)
        }
        try context.save()
    }

    @MainActor public static func save(_ context: ModelContext) throws {
        for distraction in try context.fetch(FetchDescriptor<Distraction>()) {
            try distraction.persistPrivateContent(in: context)
        }
        try context.save()
    }
}
