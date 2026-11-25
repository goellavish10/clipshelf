import AppKit
import ClipShelfCore
import SwiftUI

struct ClipboardPopoverView: View {
    @ObservedObject var model: AppModel
    @State private var confirmsClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.65)
            history
            Divider().opacity(0.65)
            footer
        }
        .frame(width: 420, height: 560)
        .background(.ultraThinMaterial)
        .alert(item: $model.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Clear unpinned history?",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                model.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned items will be kept.")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.gradient)
                    Image(systemName: "clipboard.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("ClipShelf")
                        .font(.headline)
                    Text(model.isPaused ? "Recording paused" : "Clipboard history")
                        .font(.caption)
                        .foregroundStyle(model.isPaused ? .orange : .secondary)
                }

                Spacer()

                Button {
                    model.togglePaused()
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(model.isPaused ? "Resume recording" : "Pause recording")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search copied text, links, and files", text: $model.searchText)
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.88))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    }
            )
        }
        .padding(16)
    }

    @ViewBuilder
    private var history: some View {
        if model.entries.isEmpty {
            EmptyHistoryView(isPaused: model.isPaused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.filteredEntries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No Matches")
                    .font(.headline)
                Text("Try a different search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(model.filteredEntries) { entry in
                        HistoryRow(
                            entry: entry,
                            isActive: model.activeEntryID == entry.id,
                            isDisabled: model.isRestoring,
                            model: model
                        )
                    }
                }
                .padding(10)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(historySummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Clear") {
                confirmsClear = true
            }
            .buttonStyle(.borderless)
            .disabled(model.entries.allSatisfy(\.isPinned))

            Divider()
                .frame(height: 14)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .frame(height: 43)
    }

    private var historySummary: String {
        let count = model.entries.count
        return (count == 1 ? "1 item" : "\(count) items") + " · kept 30 days"
    }
}

private struct EmptyHistoryView: View {
    let isPaused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isPaused ? "pause.circle" : "doc.on.clipboard")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(isPaused ? "Recording is paused" : "Copy something to get started")
                .font(.headline)
            Text(isPaused
                 ? "Resume recording to add new clipboard items."
                 : "Text, links, images, and Finder files will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }
}
