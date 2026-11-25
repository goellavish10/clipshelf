import AppKit
import ClipShelfCore
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var isPaused = false
    @Published private(set) var activeEntryID: UUID?
    @Published private(set) var isRestoring = false
    @Published var searchText = ""
    @Published var presentedError: PresentedError?

    var onRestoreCompleted: (() -> Void)?

    private let store: HistoryStore
    private lazy var monitor = ClipboardMonitor { [weak self] pasteboard, application in
        self?.capture(from: pasteboard, sourceApplication: application)
    }
    private let thumbnailCache = NSCache<NSUUID, NSImage>()
    private var expiryTask: Task<Void, Never>?

    init(store: HistoryStore = HistoryStore()) {
        self.store = store
        thumbnailCache.countLimit = 60
    }

    var canPin: Bool {
        entries.filter(\.isPinned).count < HistoryStore.defaultMaxPinned
    }

    var filteredEntries: [ClipboardEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.searchableText.localizedCaseInsensitiveContains(query)
                || ($0.sourceApplicationName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    func start() {
        monitor.start()
        Task {
            do {
                entries = try await store.loadEntries()
            } catch {
                show(error, title: "Couldn’t load clipboard history")
            }
        }
        expiryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60 * 60))
                guard let self, !Task.isCancelled else { return }
                if let entries = try? await self.store.removeExpired() {
                    self.entries = entries
                }
            }
        }
    }

    func stop() {
        monitor.stop()
        expiryTask?.cancel()
        expiryTask = nil
    }

    func togglePaused() {
        isPaused.toggle()
        monitor.setPaused(isPaused)
    }

    func restore(_ entry: ClipboardEntry) {
        guard !isRestoring else { return }
        isRestoring = true

        Task {
            defer { isRestoring = false }
            do {
                let items = try await store.loadItems(for: entry)
                let changeCount = try ClipboardRestorer.restore(items)
                monitor.ignore(changeCount: changeCount)
                activeEntryID = entry.id
                if let updated = try? await store.markUsed(id: entry.id) {
                    entries = updated
                }
                onRestoreCompleted?()
            } catch {
                show(error, title: "Couldn’t restore clipboard item")
            }
        }
    }

    func togglePinned(_ entry: ClipboardEntry) {
        Task {
            do {
                entries = try await store.togglePinned(id: entry.id)
            } catch {
                show(error, title: "Couldn’t update clipboard item")
            }
        }
    }

    func delete(_ entry: ClipboardEntry) {
        Task {
            do {
                entries = try await store.delete(id: entry.id)
                thumbnailCache.removeObject(forKey: entry.id as NSUUID)
                if activeEntryID == entry.id {
                    activeEntryID = nil
                }
            } catch {
                show(error, title: "Couldn’t delete clipboard item")
            }
        }
    }

    func clearHistory() {
        Task {
            do {
                entries = try await store.clearUnpinned()
                thumbnailCache.removeAllObjects()
                if let activeEntryID, !entries.contains(where: { $0.id == activeEntryID }) {
                    self.activeEntryID = nil
                }
            } catch {
                show(error, title: "Couldn’t clear clipboard history")
            }
        }
    }

    func thumbnail(for entry: ClipboardEntry) async -> NSImage? {
        let key = entry.id as NSUUID
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        do {
            guard let data = try await store.loadThumbnail(for: entry),
                  let image = NSImage(data: data) else {
                return nil
            }
            thumbnailCache.setObject(image, forKey: key)
            return image
        } catch {
            return nil
        }
    }

    private func capture(from pasteboard: NSPasteboard, sourceApplication: NSRunningApplication?) {
        guard let snapshot = ClipboardSnapshotter.capture(
            from: pasteboard,
            sourceApplication: sourceApplication
        ) else {
            return
        }

        Task {
            do {
                entries = try await store.save(snapshot)
            } catch {
                show(error, title: "Couldn’t save clipboard item")
            }
        }
    }

    private func show(_ error: Error, title: String) {
        presentedError = PresentedError(title: title, message: error.localizedDescription)
    }
}

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
