import Foundation

public enum HistoryStoreError: LocalizedError {
    case pinLimitReached(Int)

    public var errorDescription: String? {
        switch self {
        case .pinLimitReached(let limit):
            return "You can pin up to \(limit) items. Unpin one to make room."
        }
    }
}

public actor HistoryStore {
    public static let defaultRetention: TimeInterval = 30 * 24 * 60 * 60
    public static let defaultMaxPinned = 3

    private struct HistoryIndex: Codable {
        var version: Int
        var entries: [ClipboardEntry]
    }

    private static let currentVersion = 2

    private let rootURL: URL
    private let payloadsURL: URL
    private let indexURL: URL
    private let retention: TimeInterval
    private let maxPinned: Int
    private let maxBytes: Int
    private let now: @Sendable () -> Date
    private let fileManager: FileManager

    public init(
        rootURL: URL? = nil,
        retention: TimeInterval = HistoryStore.defaultRetention,
        maxPinned: Int = HistoryStore.defaultMaxPinned,
        maxBytes: Int = 1_024 * 1_024 * 1_024,
        now: @escaping @Sendable () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        let defaultRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ClipShelf", isDirectory: true)
        let selectedRoot = rootURL ?? defaultRoot

        self.rootURL = selectedRoot
        self.payloadsURL = selectedRoot.appendingPathComponent("Payloads", isDirectory: true)
        self.indexURL = selectedRoot.appendingPathComponent("history.json")
        self.retention = retention
        self.maxPinned = maxPinned
        self.maxBytes = maxBytes
        self.now = now
        self.fileManager = fileManager
    }

    public func loadEntries() throws -> [ClipboardEntry] {
        try ensureDirectories()
        var index = try readIndex()
        if index.version < Self.currentVersion {
            index.entries = migrateIdentities(index.entries)
            index.version = Self.currentVersion
        }
        index.entries = prune(index.entries)
        try writeIndex(index)
        removeOrphanedPayloads(keeping: index.entries)
        return index.entries
    }

    @discardableResult
    public func removeExpired() throws -> [ClipboardEntry] {
        var index = try readIndex()
        let before = index.entries.count
        index.entries = prune(index.entries)
        if index.entries.count != before {
            try writeIndex(index)
        }
        return index.entries
    }

    @discardableResult
    public func save(_ captured: CapturedClipboardEntry) throws -> [ClipboardEntry] {
        try ensureDirectories()
        var index = try readIndex()

        let entryDirectory = payloadDirectory(for: captured.id)
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

            let duplicates = index.entries.filter { $0.contentHash == captured.contentHash }
            index.entries.removeAll { $0.contentHash == captured.contentHash }

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
                isPinned: duplicates.contains(where: \.isPinned),
                thumbnailRelativePath: thumbnailRelativePath,
                items: storedItems
            )

            index.entries.append(entry)
            index.entries = prune(index.entries)
            try writeIndex(index)
            duplicates.forEach(removePayload(for:))
            return index.entries
        } catch {
            try? fileManager.removeItem(at: entryDirectory)
            throw error
        }
    }

    @discardableResult
    public func markUsed(id: UUID) throws -> [ClipboardEntry] {
        var index = try readIndex()
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == id }) else {
            return index.entries.sorted(by: Self.sortEntries)
        }

        index.entries[entryIndex].capturedAt = now()
        index.entries.sort(by: Self.sortEntries)
        try writeIndex(index)
        return index.entries
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

        if !index.entries[entryIndex].isPinned,
           index.entries.filter(\.isPinned).count >= maxPinned {
            throw HistoryStoreError.pinLimitReached(maxPinned)
        }

        index.entries[entryIndex].isPinned.toggle()
        // An unpinned entry past retention would be purged immediately, so restart its clock.
        if !index.entries[entryIndex].isPinned,
           index.entries[entryIndex].capturedAt < now().addingTimeInterval(-retention) {
            index.entries[entryIndex].capturedAt = now()
        }
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
        removePayload(for: removed)
        try writeIndex(index)
        return index.entries.sorted(by: Self.sortEntries)
    }

    @discardableResult
    public func clearUnpinned() throws -> [ClipboardEntry] {
        var index = try readIndex()
        let removed = index.entries.filter { !$0.isPinned }
        index.entries.removeAll { !$0.isPinned }
        removed.forEach(removePayload(for:))
        try writeIndex(index)
        return index.entries.sorted(by: Self.sortEntries)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: payloadsURL, withIntermediateDirectories: true)
    }

    private func readIndex() throws -> HistoryIndex {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return HistoryIndex(version: Self.currentVersion, entries: [])
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

    private func payloadDirectory(for id: UUID) -> URL {
        payloadsURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func removePayload(for entry: ClipboardEntry) {
        try? fileManager.removeItem(at: payloadDirectory(for: entry.id))
    }

    private func removeOrphanedPayloads(keeping entries: [ClipboardEntry]) {
        let known = Set(entries.map(\.id.uuidString))
        let directories = (try? fileManager.contentsOfDirectory(atPath: payloadsURL.path)) ?? []
        for name in directories where !known.contains(name) && UUID(uuidString: name) != nil {
            try? fileManager.removeItem(at: payloadsURL.appendingPathComponent(name, isDirectory: true))
        }
    }

    // Version 1 hashed every representation; re-key on plain text and merge the duplicates that left behind.
    private func migrateIdentities(_ entries: [ClipboardEntry]) -> [ClipboardEntry] {
        var merged: [String: ClipboardEntry] = [:]
        for var entry in entries.sorted(by: { $0.capturedAt > $1.capturedAt }) {
            if let items = try? loadItems(for: entry) {
                entry.contentHash = ContentHasher.identity(items: items.map { item in
                    CapturedClipboardItem(representations: item.representations.map {
                        CapturedRepresentation(typeIdentifier: $0.typeIdentifier, data: $0.data)
                    })
                })
            }
            if var newer = merged[entry.contentHash] {
                newer.isPinned = newer.isPinned || entry.isPinned
                merged[entry.contentHash] = newer
                removePayload(for: entry)
            } else {
                merged[entry.contentHash] = entry
            }
        }
        return Array(merged.values)
    }

    private func prune(_ entries: [ClipboardEntry]) -> [ClipboardEntry] {
        let cutoff = now().addingTimeInterval(-retention)
        var kept: [ClipboardEntry] = []
        for entry in entries.sorted(by: Self.sortEntries) {
            if !entry.isPinned && entry.capturedAt < cutoff {
                removePayload(for: entry)
            } else {
                kept.append(entry)
            }
        }

        var totalBytes = kept.reduce(0) { $0 + $1.byteCount }
        while totalBytes > maxBytes {
            guard let removalIndex = kept.lastIndex(where: { !$0.isPinned }) else { break }
            let removed = kept.remove(at: removalIndex)
            totalBytes -= removed.byteCount
            removePayload(for: removed)
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
