import Foundation
import Testing
import ClipShelfCore

struct QuickPasteSelectionTests {
    @Test
    func withoutPinsShowsThreeMostRecent() {
        let entries = [
            entry("A", at: 4),
            entry("B", at: 3),
            entry("C", at: 2),
            entry("D", at: 1)
        ]

        #expect(QuickPasteSelection.entries(from: entries).map(\.title) == ["A", "B", "C"])
    }

    @Test
    func showsFirstPinThenTwoMostRecent() {
        let entries = [
            entry("Pin newer", at: 10, pinned: true),
            entry("Pin older", at: 5, pinned: true),
            entry("Pin oldest", at: 1, pinned: true),
            entry("A", at: 9),
            entry("B", at: 8),
            entry("C", at: 7)
        ]

        #expect(QuickPasteSelection.entries(from: entries).map(\.title) == ["Pin newer", "A", "B"])
    }

    @Test
    func showsWhatExistsWhenHistoryIsShort() {
        #expect(QuickPasteSelection.entries(from: [entry("Pin", at: 1, pinned: true)]).map(\.title) == ["Pin"])
        #expect(QuickPasteSelection.entries(from: [entry("A", at: 1)]).map(\.title) == ["A"])
        #expect(QuickPasteSelection.entries(from: []).isEmpty)
    }

    private func entry(_ title: String, at seconds: TimeInterval, pinned: Bool = false) -> ClipboardEntry {
        ClipboardEntry(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: seconds),
            kind: .text,
            title: title,
            searchableText: title,
            sourceApplicationName: nil,
            sourceBundleIdentifier: nil,
            contentHash: title,
            byteCount: title.utf8.count,
            isPinned: pinned,
            thumbnailRelativePath: nil,
            items: []
        )
    }
}
