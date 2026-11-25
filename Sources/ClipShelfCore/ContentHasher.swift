import CryptoKit
import Foundation

public enum ContentHasher {
    private static let identityTypes: Set<String> = ["public.utf8-plain-text", "public.file-url"]

    /// Apps attach different HTML/RTF to the same text, so duplicates are matched on plain text and file URLs.
    public static func identity(items: [CapturedClipboardItem]) -> String {
        let keyItems = items.map { item in
            CapturedClipboardItem(
                representations: item.representations.filter { identityTypes.contains($0.typeIdentifier) }
            )
        }
        guard keyItems.contains(where: { !$0.representations.isEmpty }) else {
            return hash(items: items)
        }
        return hash(items: keyItems)
    }

    public static func hash(items: [CapturedClipboardItem]) -> String {
        var hasher = SHA256()

        for item in items {
            appendLength(item.representations.count, to: &hasher)
            for representation in item.representations {
                let typeData = Data(representation.typeIdentifier.utf8)
                appendLength(typeData.count, to: &hasher)
                hasher.update(data: typeData)
                appendLength(representation.data.count, to: &hasher)
                hasher.update(data: representation.data)
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func appendLength(_ value: Int, to hasher: inout SHA256) {
        var length = UInt64(value).bigEndian
        withUnsafeBytes(of: &length) { bytes in
            hasher.update(data: Data(bytes))
        }
    }
}
