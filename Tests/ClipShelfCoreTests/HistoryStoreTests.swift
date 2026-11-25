import Foundation
import Testing
@testable import ClipShelfCore

struct HistoryStoreTests {
    private static let day: TimeInterval = 24 * 60 * 60

    @Test
    func savesLoadsAndDeduplicatesEntries() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(rootURL: root, now: { Date(timeIntervalSince1970: 30) })

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
    func recopiedTextMovesToTopEvenWithDifferentFormatting() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(rootURL: root, now: { Date(timeIntervalSince1970: 100) })

        _ = try await store.save(makeEntry(text: "Repeat", html: "<b>Repeat</b>", capturedAt: Date(timeIntervalSince1970: 1)))
        _ = try await store.save(makeEntry(text: "Other", capturedAt: Date(timeIntervalSince1970: 2)))
        let entries = try await store.save(
            makeEntry(text: "Repeat", html: "<i>Repeat</i>", capturedAt: Date(timeIntervalSince1970: 3))
        )

        #expect(entries.map(\.title) == ["Repeat", "Other"])
        #expect(payloadDirectoryCount(root) == 2)
    }

    @Test
    func markUsedMovesEntryToTop() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(rootURL: root, now: { Date(timeIntervalSince1970: 100) })

        let older = try await store.save(makeEntry(text: "Older", capturedAt: Date(timeIntervalSince1970: 1)))[0]
        _ = try await store.save(makeEntry(text: "Newer", capturedAt: Date(timeIntervalSince1970: 2)))
        let entries = try await store.markUsed(id: older.id)

        #expect(entries.map(\.title) == ["Older", "Newer"])
    }

    @Test
    func historySurvivesRestart() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 100 * Self.day)

        _ = try await HistoryStore(rootURL: root, now: { now })
            .save(makeEntry(text: "Persisted", capturedAt: now.addingTimeInterval(-29 * Self.day)))
        let entries = try await HistoryStore(rootURL: root, now: { now }).loadEntries()

        #expect(entries.map(\.title) == ["Persisted"])
    }

    @Test
    func removesEntriesOlderThanThirtyDaysAndTheirPayloads() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date(timeIntervalSince1970: 100 * Self.day)
        let clock = Clock(start)
        let store = HistoryStore(rootURL: root, now: { clock.now })

        _ = try await store.save(makeEntry(text: "Old", capturedAt: start))
        let pinned = try await store.save(makeEntry(text: "Pinned", capturedAt: start))
            .first { $0.title == "Pinned" }!
        _ = try await store.togglePinned(id: pinned.id)
        _ = try await store.save(makeEntry(text: "Recent", capturedAt: start.addingTimeInterval(20 * Self.day)))

        clock.now = start.addingTimeInterval(31 * Self.day)
        let entries = try await store.removeExpired()

        #expect(entries.map(\.title) == ["Pinned", "Recent"])
        #expect(payloadDirectoryCount(root) == 2)
    }

    @Test
    func pinningIsLimitedToThree() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(rootURL: root, now: { Date(timeIntervalSince1970: 100) })

        var entries: [ClipboardEntry] = []
        for (offset, text) in ["A", "B", "C", "D"].enumerated() {
            entries = try await store.save(makeEntry(text: text, capturedAt: Date(timeIntervalSince1970: Double(offset))))
        }
        for title in ["A", "B", "C"] {
            _ = try await store.togglePinned(id: entries.first { $0.title == title }!.id)
        }

        let fourth = entries.first { $0.title == "D" }!.id
        await #expect(throws: HistoryStoreError.self) {
            try await store.togglePinned(id: fourth)
        }

        let reloaded = try await store.loadEntries()
        #expect(reloaded.map(\.isPinned) == [true, true, true, false])
        #expect(reloaded.map(\.title) == ["C", "B", "A", "D"])
    }

    @Test
    func removesOldestEntryOverTheByteLimit() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(rootURL: root, maxBytes: 8, now: { Date(timeIntervalSince1970: 100) })

        _ = try await store.save(makeEntry(text: "One", capturedAt: Date(timeIntervalSince1970: 1)))
        _ = try await store.save(makeEntry(text: "Two", capturedAt: Date(timeIntervalSince1970: 2)))
        let entries = try await store.save(makeEntry(text: "Three", capturedAt: Date(timeIntervalSince1970: 3)))

        #expect(entries.map(\.title) == ["Three", "Two"])
    }

    @Test
    func clearKeepsPinnedEntries() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(rootURL: root, now: { Date(timeIntervalSince1970: 100) })

        var entries = try await store.save(makeEntry(text: "Pinned", capturedAt: Date(timeIntervalSince1970: 1)))
        _ = try await store.save(makeEntry(text: "Disposable", capturedAt: Date(timeIntervalSince1970: 2)))
        entries = try await store.togglePinned(id: entries[0].id)
        entries = try await store.clearUnpinned()

        #expect(entries.count == 1)
        #expect(entries[0].title == "Pinned")
        #expect(entries[0].isPinned)
    }

    @Test
    func migratesVersionOneDuplicates() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let now: @Sendable () -> Date = { Date(timeIntervalSince1970: 100) }
        let store = HistoryStore(rootURL: root, now: now)

        let older = makeEntry(text: "Same", html: "<b>Same</b>", capturedAt: Date(timeIntervalSince1970: 1), legacyHash: true)
        let newer = makeEntry(text: "Same", html: "<i>Same</i>", capturedAt: Date(timeIntervalSince1970: 2), legacyHash: true)
        _ = try await store.save(older)
        _ = try await store.save(newer)

        let indexURL = root.appendingPathComponent("history.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as! [String: Any]
        json["version"] = 1
        try JSONSerialization.data(withJSONObject: json).write(to: indexURL)

        let entries = try await HistoryStore(rootURL: root, now: now).loadEntries()

        #expect(entries.count == 1)
        #expect(entries[0].id == newer.id)
        #expect(payloadDirectoryCount(root) == 1)
    }

    private func makeEntry(
        text: String,
        html: String? = nil,
        capturedAt: Date,
        legacyHash: Bool = false
    ) -> CapturedClipboardEntry {
        var representations = [
            CapturedRepresentation(typeIdentifier: "public.utf8-plain-text", data: Data(text.utf8))
        ]
        if let html {
            representations.append(CapturedRepresentation(typeIdentifier: "public.html", data: Data(html.utf8)))
        }
        let item = CapturedClipboardItem(representations: representations)
        return CapturedClipboardEntry(
            capturedAt: capturedAt,
            kind: html == nil ? .text : .richText,
            title: text,
            searchableText: text,
            contentHash: legacyHash ? ContentHasher.hash(items: [item]) : ContentHasher.identity(items: [item]),
            byteCount: text.utf8.count,
            items: [item]
        )
    }

    private func payloadDirectoryCount(_ root: URL) -> Int {
        let payloads = root.appendingPathComponent("Payloads", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(atPath: payloads.path).count) ?? 0
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipShelfTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}
