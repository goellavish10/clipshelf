import Foundation

public actor HistoryStore {
    private struct HistoryIndex: Codable {
        let version: Int
        var entries: [ClipboardEntry]
    }

    private let rootURL: URL
    private let payloadsURL: URL
    private let indexURL: URL
    private let maxEntries: Int
    private let maxBytes: Int
    private let fileManager: FileManager

    public init(
        rootURL: URL? = nil,
        maxEntries: Int = 200,
        maxBytes: Int = 300 * 1_024 * 1_024,
        fileManager: FileManager = .default
    ) {
        let defaultRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ClipShelf", isDirectory: true)
        let selectedRoot = rootURL ?? defaultRoot

        self.rootURL = selectedRoot
        self.payloadsURL = selectedRoot.appendingPathComponent("Payloads", isDirectory: true)
        self.indexURL = selectedRoot.appendingPathComponent("history.json")
        self.maxEntries = maxEntries
        self.maxBytes = maxBytes
        self.fileManager = fileManager
    }

    public func loadEntries() throws -> [ClipboardEntry] {
        try ensureDirectories()
        return try readIndex().entries.sorted(by: Self.sortEntries)
    }

    @discardableResult
    public func save(_ captured: CapturedClipboardEntry) throws -> [ClipboardEntry] {
        try ensureDirectories()
        var index = try readIndex()

        if let duplicateIndex = index.entries.firstIndex(where: { $0.contentHash == captured.contentHash }) {
            index.entries[duplicateIndex].capturedAt = captured.capturedAt
            index.entries.sort(by: Self.sortEntries)
            try writeIndex(index)
            return index.entries
        }

        let entryDirectory = payloadsURL.appendingPathComponent(captured.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: entryDirectory, withIntermediateDirectories: true)

        do {
            var storedItems: [StoredClipboardItem] = []

            for (itemIndex, item) in captured.items.enumerated() {
                var storedRepresentations: [StoredRepresentation] = []
                for (representationIndex, representation) in item.representations.enumerated() {
                    let fileName = "item-\(itemIndex)-representation-\(representationIndex).bin"
                    let relativePath = "Payloads/\(captured.id.uuidString)/\(fileName)"
                    let fileURL = rootURL.appendingPathComponent(relativePath)
                    try representation.data.write(to: fileURL, options: .atomic)
                    storedRepresentations.append(
                        StoredRepresentation(
                            typeIdentifier: representation.typeIdentifier,
                            relativePath: relativePath,
                            byteCount: representation.data.count
                        )
                    )
                }
                storedItems.append(StoredClipboardItem(representations: storedRepresentations))
            }

            var thumbnailRelativePath: String?
            if let thumbnailData = captured.thumbnailData {
                let relativePath = "Payloads/\(captured.id.uuidString)/thumbnail.png"
                try thumbnailData.write(
                    to: rootURL.appendingPathComponent(relativePath),
                    options: .atomic
                )
                thumbnailRelativePath = relativePath
            }

            let entry = ClipboardEntry(
                id: captured.id,
                capturedAt: captured.capturedAt,
                kind: captured.kind,
                title: captured.title,
                searchableText: captured.searchableText,
                sourceApplicationName: captured.sourceApplicationName,
                sourceBundleIdentifier: captured.sourceBundleIdentifier,
                contentHash: captured.contentHash,
                byteCount: captured.byteCount,
                isPinned: false,
                thumbnailRelativePath: thumbnailRelativePath,
                items: storedItems
            )

            index.entries.append(entry)
            index.entries.sort(by: Self.sortEntries)
            index.entries = try prune(index.entries)
            try writeIndex(index)
            return index.entries
        } catch {
            try? fileManager.removeItem(at: entryDirectory)
            throw error
        }
    }

    public func loadItems(for entry: ClipboardEntry) throws -> [LoadedClipboardItem] {
        try entry.items.map { item in
            let representations = try item.representations.map { representation in
                let data = try Data(contentsOf: rootURL.appendingPathComponent(representation.relativePath))
                return LoadedRepresentation(typeIdentifier: representation.typeIdentifier, data: data)
            }
            return LoadedClipboardItem(representations: representations)
        }
    }

    public func loadThumbnail(for entry: ClipboardEntry) throws -> Data? {
        guard let relativePath = entry.thumbnailRelativePath else { return nil }
        return try Data(contentsOf: rootURL.appendingPathComponent(relativePath))
    }

    @discardableResult
    public func togglePinned(id: UUID) throws -> [ClipboardEntry] {
        var index = try readIndex()
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == id }) else {
            return index.entries.sorted(by: Self.sortEntries)
        }

        index.entries[entryIndex].isPinned.toggle()
        index.entries.sort(by: Self.sortEntries)
        try writeIndex(index)
        return index.entries
    }

    @discardableResult
    public func delete(id: UUID) throws -> [ClipboardEntry] {
        var index = try readIndex()
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == id }) else {
            return index.entries.sorted(by: Self.sortEntries)
        }

        let removed = index.entries.remove(at: entryIndex)
        try? fileManager.removeItem(
            at: payloadsURL.appendingPathComponent(removed.id.uuidString, isDirectory: true)
        )
        try writeIndex(index)
        return index.entries.sorted(by: Self.sortEntries)
    }

    @discardableResult
    public func clearUnpinned() throws -> [ClipboardEntry] {
        var index = try readIndex()
        let removed = index.entries.filter { !$0.isPinned }
        index.entries.removeAll { !$0.isPinned }

        for entry in removed {
            try? fileManager.removeItem(
                at: payloadsURL.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            )
        }

        try writeIndex(index)
        return index.entries.sorted(by: Self.sortEntries)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: payloadsURL, withIntermediateDirectories: true)
    }

    private func readIndex() throws -> HistoryIndex {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return HistoryIndex(version: 1, entries: [])
        }

        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HistoryIndex.self, from: data)
    }

    private func writeIndex(_ index: HistoryIndex) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    private func prune(_ entries: [ClipboardEntry]) throws -> [ClipboardEntry] {
        var kept = entries.sorted(by: Self.sortEntries)
        var unpinnedCount = kept.filter { !$0.isPinned }.count
        var totalBytes = kept.reduce(0) { $0 + $1.byteCount }

        while unpinnedCount > maxEntries || totalBytes > maxBytes {
            guard let removalIndex = kept.lastIndex(where: { !$0.isPinned }) else { break }
            let removed = kept.remove(at: removalIndex)
            unpinnedCount -= 1
            totalBytes -= removed.byteCount
            try? fileManager.removeItem(
                at: payloadsURL.appendingPathComponent(removed.id.uuidString, isDirectory: true)
            )
        }

        return kept
    }

    private static func sortEntries(_ lhs: ClipboardEntry, _ rhs: ClipboardEntry) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned
        }
        return lhs.capturedAt > rhs.capturedAt
    }
}
