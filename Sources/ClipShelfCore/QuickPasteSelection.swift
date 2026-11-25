import Foundation

public enum QuickPasteSelection {
    public static let limit = 3

    public static func entries(from entries: [ClipboardEntry]) -> [ClipboardEntry] {
        let newestFirst = entries.sorted { $0.capturedAt > $1.capturedAt }
        let pin = newestFirst.first(where: \.isPinned)
        let recent = newestFirst.filter { !$0.isPinned }
        return (pin.map { [$0] } ?? []) + recent.prefix(limit - (pin == nil ? 0 : 1))
    }
}
