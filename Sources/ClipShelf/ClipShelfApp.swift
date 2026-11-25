import AppKit
import SwiftUI

@main
struct ClipShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commandsRemoved()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let model = AppModel()
    private weak var previouslyActiveApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "clipboard",
                accessibilityDescription: "ClipShelf clipboard history"
            )
            button.image?.isTemplate = true
            button.toolTip = "ClipShelf"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        self.statusItem = statusItem

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: ClipboardPopoverView(model: model)
        )

        model.onRestoreCompleted = { [weak self] in
            self?.finishSelection()
        }
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        guard let button = statusItem?.button else { return }
        previouslyActiveApplication = NSWorkspace.shared.frontmostApplication
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func finishSelection() {
        popover.performClose(nil)
        guard let application = previouslyActiveApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        application.activate(options: [.activateIgnoringOtherApps])
    }
}
