import AppKit
import Carbon.HIToolbox
import ClipShelfCore
import SwiftUI

@MainActor
final class QuickPasteState: ObservableObject {
    @Published var entries: [ClipboardEntry] = []
    @Published var highlightedIndex = 0
}

@MainActor
final class QuickPasteController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let state = QuickPasteState()
    private let panel: QuickPastePanel
    private let hostingView: NSHostingView<QuickPasteView>
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        panel = QuickPastePanel()
        hostingView = NSHostingView(rootView: QuickPasteView(state: state, model: model, onSelect: { _ in }))
        super.init()

        hostingView.rootView = QuickPasteView(state: state, model: model) { [weak self] index in
            self?.select(index)
        }
        panel.contentView = hostingView
        panel.delegate = self
    }

    func toggle() {
        if panel.isVisible {
            close()
        } else {
            show()
        }
    }

    private func show() {
        TypingTarget.requestTrustOnce()

        state.entries = model.quickPasteEntries
        state.highlightedIndex = 0
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        panel.setFrame(NSRect(origin: origin(for: size), size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return nil
        }
        // We never become the active app, so clicks elsewhere don't resign our panel.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func handle(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_ANSI_1, kVK_ANSI_Keypad1: select(0)
        case kVK_ANSI_2, kVK_ANSI_Keypad2: select(1)
        case kVK_ANSI_3, kVK_ANSI_Keypad3: select(2)
        case kVK_DownArrow: moveHighlight(by: 1)
        case kVK_UpArrow: moveHighlight(by: -1)
        case kVK_Return, kVK_ANSI_KeypadEnter: select(state.highlightedIndex)
        case kVK_Escape: close()
        default: break
        }
    }

    private func moveHighlight(by offset: Int) {
        guard !state.entries.isEmpty else { return }
        let count = state.entries.count
        state.highlightedIndex = (state.highlightedIndex + offset + count) % count
    }

    private func select(_ index: Int) {
        guard state.entries.indices.contains(index) else { return }
        let entry = state.entries[index]
        close()
        model.restore(entry) {
            TypingTarget.paste()
        }
    }

    private func origin(for size: NSSize) -> NSPoint {
        let gap: CGFloat = 6
        let anchor = TypingTarget.caretRect() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)

        var origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - gap)
        if origin.y < visible.minY {
            origin.y = anchor.maxY + gap
        }
        origin.x = min(max(origin.x, visible.minX + gap), visible.maxX - size.width - gap)
        origin.y = min(max(origin.y, visible.minY + gap), visible.maxY - size.height - gap)
        return origin
    }
}

private final class QuickPastePanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}

struct QuickPasteView: View {
    @ObservedObject var state: QuickPasteState
    @ObservedObject var model: AppModel
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if state.entries.isEmpty {
                Text("Nothing copied yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
            } else {
                ForEach(Array(state.entries.enumerated()), id: \.element.id) { index, entry in
                    QuickPasteRow(
                        entry: entry,
                        number: index + 1,
                        isHighlighted: index == state.highlightedIndex,
                        model: model
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(index) }
                    .onHover { hovering in
                        if hovering { state.highlightedIndex = index }
                    }
                }
            }
        }
        .padding(5)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        }
    }
}

private struct QuickPasteRow: View {
    let entry: ClipboardEntry
    let number: Int
    let isHighlighted: Bool
    @ObservedObject var model: AppModel

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 9) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isHighlighted ? Color.white : Color.secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHighlighted ? Color.accentColor : Color.primary.opacity(0.08))
                )

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: entry.kind.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(entry.kind.tint)
                    .frame(width: 26)
            }

            Text(entry.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .task(id: entry.id) {
            guard entry.kind == .image else { return }
            thumbnail = await model.thumbnail(for: entry)
        }
    }
}
