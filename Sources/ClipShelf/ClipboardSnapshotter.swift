import AppKit
import ClipShelfCore
import UniformTypeIdentifiers

@MainActor
enum ClipboardSnapshotter {
    private static let maximumRepresentationBytes = 25 * 1_024 * 1_024
    private static let maximumEntryBytes = 30 * 1_024 * 1_024

    private static let explicitlySupportedTypes: Set<String> = [
        NSPasteboard.PasteboardType.string.rawValue,
        NSPasteboard.PasteboardType.rtf.rawValue,
        NSPasteboard.PasteboardType.rtfd.rawValue,
        NSPasteboard.PasteboardType.html.rawValue,
        NSPasteboard.PasteboardType.png.rawValue,
        NSPasteboard.PasteboardType.tiff.rawValue,
        NSPasteboard.PasteboardType.fileURL.rawValue,
        NSPasteboard.PasteboardType.URL.rawValue,
        "public.jpeg",
        "public.utf16-external-plain-text",
        "com.apple.flat-rtfd"
    ]

    static func capture(
        from pasteboard: NSPasteboard,
        sourceApplication: NSRunningApplication?
    ) -> CapturedClipboardEntry? {
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else {
            return nil
        }

        var capturedItems: [CapturedClipboardItem] = []
        var totalBytes = 0
        var plainTexts: [String] = []
        var webURLs: [String] = []
        var fileNames: [String] = []
        var firstImageData: Data?
        var containsRichText = false

        for pasteboardItem in pasteboardItems {
            var representations: [CapturedRepresentation] = []

            if let text = pasteboardItem.string(forType: .string), !text.isEmpty {
                plainTexts.append(text)
            }

            if let fileURLString = pasteboardItem.string(forType: .fileURL),
               let fileURL = URL(string: fileURLString) {
                fileNames.append(fileURL.lastPathComponent)
            }

            if let urlString = pasteboardItem.string(forType: .URL),
               !urlString.hasPrefix("file:") {
                webURLs.append(urlString)
            }

            for type in pasteboardItem.types where shouldCapture(type) {
                guard let data = pasteboardItem.data(forType: type),
                      !data.isEmpty,
                      data.count <= maximumRepresentationBytes,
                      totalBytes + data.count <= maximumEntryBytes else {
                    continue
                }

                totalBytes += data.count
                representations.append(
                    CapturedRepresentation(typeIdentifier: type.rawValue, data: data)
                )

                if isImage(type), firstImageData == nil {
                    firstImageData = data
                }

                if type == .rtf || type == .rtfd || type == .html || type.rawValue == "com.apple.flat-rtfd" {
                    containsRichText = true
                }
            }

            if !representations.isEmpty {
                capturedItems.append(CapturedClipboardItem(representations: representations))
            }
        }

        guard !capturedItems.isEmpty else { return nil }

        let kind: ClipboardKind
        let title: String

        if !fileNames.isEmpty {
            kind = .files
            title = fileNames.count == 1
                ? fileNames[0]
                : "\(fileNames.count) files — \(fileNames.prefix(2).joined(separator: ", "))"
        } else if firstImageData != nil {
            kind = .image
            title = "Image"
        } else if let url = webURLs.first {
            kind = .url
            title = compact(url, limit: 160)
        } else if let text = plainTexts.first {
            kind = containsRichText ? .richText : .text
            title = compact(text, limit: 180)
        } else {
            kind = .unknown
            title = "Clipboard item"
        }

        let searchableParts = plainTexts + webURLs + fileNames + [sourceApplication?.localizedName ?? ""]
        let searchableText = searchableParts.joined(separator: "\n")
        let thumbnail = firstImageData.flatMap(makeThumbnail(from:))
        let contentHash = ContentHasher.identity(items: capturedItems)

        return CapturedClipboardEntry(
            kind: kind,
            title: title,
            searchableText: searchableText,
            sourceApplicationName: sourceApplication?.localizedName,
            sourceBundleIdentifier: sourceApplication?.bundleIdentifier,
            contentHash: contentHash,
            byteCount: totalBytes,
            thumbnailData: thumbnail,
            items: capturedItems
        )
    }

    private static func shouldCapture(_ type: NSPasteboard.PasteboardType) -> Bool {
        if explicitlySupportedTypes.contains(type.rawValue) {
            return true
        }

        guard let uniformType = UTType(type.rawValue) else { return false }
        return uniformType.conforms(to: .text)
            || uniformType.conforms(to: .image)
            || uniformType.conforms(to: .url)
    }

    private static func isImage(_ type: NSPasteboard.PasteboardType) -> Bool {
        guard let uniformType = UTType(type.rawValue) else { return false }
        return uniformType.conforms(to: .image)
    }

    private static func compact(_ value: String, limit: Int) -> String {
        let singleLine = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit - 1)) + "…"
    }

    private static func makeThumbnail(from data: Data) -> Data? {
        guard let source = NSImage(data: data), source.size.width > 0, source.size.height > 0 else {
            return nil
        }

        let canvas = NSSize(width: 160, height: 112)
        let scale = min(canvas.width / source.size.width, canvas.height / source.size.height)
        let destinationSize = NSSize(
            width: max(1, source.size.width * scale),
            height: max(1, source.size.height * scale)
        )
        let destinationRect = NSRect(
            x: (canvas.width - destinationSize.width) / 2,
            y: (canvas.height - destinationSize.height) / 2,
            width: destinationSize.width,
            height: destinationSize.height
        )

        let thumbnail = NSImage(size: canvas)
        thumbnail.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: destinationRect, from: .zero, operation: .sourceOver, fraction: 1)
        thumbnail.unlockFocus()

        guard let tiff = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
