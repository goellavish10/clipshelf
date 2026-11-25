import Foundation
import Testing
@testable import ClipShelfCore

struct HistoryStoreTests {
    @Test
    func savesLoadsAndDeduplicatesEntries() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(rootURL: root)

        let first = makeEntry(text: "Hello", capturedAt: Date(timeIntervalSince1970: 10))
        let second = makeEntry(text: "Hello", capturedAt: Date(timeIntervalSince1970: 20))

        _ = try await store.save(first)
        let entries = try await store.save(second)

        #expect(entries.count == 1)
        #expect(entries[0].capturedAt == second.capturedAt)

        let loaded = try await store.loadItems(for: entries[0])
        #expect(loaded.count == 1)
        #expect(String(data: loaded[0].representations[0].data, encoding: .utf8) == "Hello")
    }

    @Test
    func removesOldestEntryAtTheLimit() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(rootURL: root, maxEntries: 2)

        _ = try await store.save(makeEntry(text: "One", capturedAt: Date(timeIntervalSince1970: 1)))
        _ = try await store.save(makeEntry(text: "Two", capturedAt: Date(timeIntervalSince1970: 2)))
        let entries = try await store.save(makeEntry(text: "Three", capturedAt: Date(timeIntervalSince1970: 3)))

        #expect(entries.map(\.title) == ["Three", "Two"])
    }

    @Test
    func clearKeepsPinnedEntries() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(rootURL: root)

        var entries = try await store.save(makeEntry(text: "Pinned", capturedAt: Date(timeIntervalSince1970: 1)))
        _ = try await store.save(makeEntry(text: "Disposable", capturedAt: Date(timeIntervalSince1970: 2)))
        entries = try await store.togglePinned(id: entries[0].id)
        entries = try await store.clearUnpinned()

        #expect(entries.count == 1)
        #expect(entries[0].title == "Pinned")
        #expect(entries[0].isPinned)
    }

    private func makeEntry(text: String, capturedAt: Date) -> CapturedClipboardEntry {
        let representation = CapturedRepresentation(
            typeIdentifier: "public.utf8-plain-text",
            data: Data(text.utf8)
        )
        let item = CapturedClipboardItem(representations: [representation])
        return CapturedClipboardEntry(
            capturedAt: capturedAt,
            kind: .text,
            title: text,
            searchableText: text,
            contentHash: ContentHasher.hash(items: [item]),
            byteCount: representation.data.count,
            items: [item]
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipShelfTests-\(UUID().uuidString)", isDirectory: true)
    }
}
