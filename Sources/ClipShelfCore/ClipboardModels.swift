import Foundation

public enum ClipboardKind: String, Codable, Sendable {
    case text
    case richText
    case url
    case image
    case files
    case unknown
}

public struct StoredRepresentation: Codable, Hashable, Sendable {
    public let typeIdentifier: String
    public let relativePath: String
    public let byteCount: Int

    public init(typeIdentifier: String, relativePath: String, byteCount: Int) {
        self.typeIdentifier = typeIdentifier
        self.relativePath = relativePath
        self.byteCount = byteCount
    }
}

public struct StoredClipboardItem: Codable, Hashable, Sendable {
    public let representations: [StoredRepresentation]

    public init(representations: [StoredRepresentation]) {
        self.representations = representations
    }
}

public struct ClipboardEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var capturedAt: Date
    public let kind: ClipboardKind
    public let title: String
    public let searchableText: String
    public let sourceApplicationName: String?
    public let sourceBundleIdentifier: String?
    public var contentHash: String
    public let byteCount: Int
    public var isPinned: Bool
    public let thumbnailRelativePath: String?
    public let items: [StoredClipboardItem]

    public init(
        id: UUID,
        capturedAt: Date,
        kind: ClipboardKind,
        title: String,
        searchableText: String,
        sourceApplicationName: String?,
        sourceBundleIdentifier: String?,
        contentHash: String,
        byteCount: Int,
        isPinned: Bool,
        thumbnailRelativePath: String?,
        items: [StoredClipboardItem]
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.kind = kind
        self.title = title
        self.searchableText = searchableText
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.contentHash = contentHash
        self.byteCount = byteCount
        self.isPinned = isPinned
        self.thumbnailRelativePath = thumbnailRelativePath
        self.items = items
    }
}

public struct CapturedRepresentation: Sendable {
    public let typeIdentifier: String
    public let data: Data

    public init(typeIdentifier: String, data: Data) {
        self.typeIdentifier = typeIdentifier
        self.data = data
    }
}

public struct CapturedClipboardItem: Sendable {
    public let representations: [CapturedRepresentation]

    public init(representations: [CapturedRepresentation]) {
        self.representations = representations
    }
}

public struct CapturedClipboardEntry: Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let kind: ClipboardKind
    public let title: String
    public let searchableText: String
    public let sourceApplicationName: String?
    public let sourceBundleIdentifier: String?
    public let contentHash: String
    public let byteCount: Int
    public let thumbnailData: Data?
    public let items: [CapturedClipboardItem]

    public init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        kind: ClipboardKind,
        title: String,
        searchableText: String,
        sourceApplicationName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        contentHash: String,
        byteCount: Int,
        thumbnailData: Data? = nil,
        items: [CapturedClipboardItem]
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.kind = kind
        self.title = title
        self.searchableText = searchableText
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.contentHash = contentHash
        self.byteCount = byteCount
        self.thumbnailData = thumbnailData
        self.items = items
    }
}

public struct LoadedRepresentation: Sendable {
    public let typeIdentifier: String
    public let data: Data

    public init(typeIdentifier: String, data: Data) {
        self.typeIdentifier = typeIdentifier
        self.data = data
    }
}

public struct LoadedClipboardItem: Sendable {
    public let representations: [LoadedRepresentation]

    public init(representations: [LoadedRepresentation]) {
        self.representations = representations
    }
}
