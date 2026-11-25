import AppKit
import ClipShelfCore
import SwiftUI

struct HistoryRow: View {
    let entry: ClipboardEntry
    let isActive: Bool
    let isDisabled: Bool
    @ObservedObject var model: AppModel

    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    var body: some View {
        Button {
            model.restore(entry)
        } label: {
            HStack(spacing: 12) {
                leadingVisual

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(entry.kind == .text || entry.kind == .richText ? 2 : 1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 5) {
                        if let source = entry.sourceApplicationName, source != "ClipShelf" {
                            Text(source)
                            Text("·")
                        }
                        Text(entry.capturedAt, style: .relative)
                        Text("·")
                        Text(ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .help("Ready to paste")
                } else if isHovered {
                    Image(systemName: "return")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .contextMenu {
            if entry.isPinned {
                Button("Unpin") {
                    model.togglePinned(entry)
                }
            } else {
                Button(model.canPin ? "Pin to Top" : "Pin to Top (\(HistoryStore.defaultMaxPinned) max)") {
                    model.togglePinned(entry)
                }
                .disabled(!model.canPin)
            }
            Divider()
            Button("Delete", role: .destructive) {
                model.delete(entry)
            }
        }
        .task(id: entry.id) {
            guard entry.kind == .image else { return }
            thumbnail = await model.thumbnail(for: entry)
        }
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 46)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(entry.kind.tint.opacity(0.13))
                Image(systemName: entry.kind.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(entry.kind.tint)
            }
            .frame(width: 44, height: 44)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(
                isActive
                    ? Color.accentColor.opacity(0.11)
                    : Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.95 : 0.62)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            }
    }
}

private extension ClipboardKind {
    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .url: "link"
        case .image: "photo"
        case .files: "doc.on.doc"
        case .unknown: "clipboard"
        }
    }

    var tint: Color {
        switch self {
        case .text: .blue
        case .richText: .indigo
        case .url: .cyan
        case .image: .purple
        case .files: .orange
        case .unknown: .secondary
        }
    }
}
