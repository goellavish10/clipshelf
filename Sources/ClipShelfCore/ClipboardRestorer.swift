import AppKit

@MainActor
public enum ClipboardRestorer {
    public static func restore(
        _ loadedItems: [LoadedClipboardItem],
        to pasteboard: NSPasteboard = .general
    ) throws -> Int {
        let pasteboardItems: [NSPasteboardItem] = loadedItems.compactMap { loadedItem in
            let item = NSPasteboardItem()
            var wroteRepresentation = false

            for representation in loadedItem.representations {
                let type = NSPasteboard.PasteboardType(representation.typeIdentifier)
                if item.setData(representation.data, forType: type) {
                    wroteRepresentation = true
                }
            }

            return wroteRepresentation ? item : nil
        }

        guard !pasteboardItems.isEmpty else {
            throw ClipboardRestoreError.noRepresentations
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects(pasteboardItems) else {
            throw ClipboardRestoreError.writeFailed
        }
        return pasteboard.changeCount
    }
}

public enum ClipboardRestoreError: LocalizedError {
    case noRepresentations
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .noRepresentations:
            return "This clipboard item no longer has any data to restore."
        case .writeFailed:
            return "macOS could not place this item on the clipboard."
        }
    }
}
