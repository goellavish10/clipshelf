import AppKit
import Carbon.HIToolbox
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var outsideClickMonitor: Any?
    private let model = AppModel()
    private lazy var quickPaste = QuickPasteController(model: model)
    private var quickPasteHotKey: HotKey?
    private weak var previouslyActiveApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = menuBarIcon()
            button.toolTip = "ClipShelf"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        self.statusItem = statusItem

        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: ClipboardPopoverView(model: model)
        )

        model.onRestoreCompleted = { [weak self] in
            self?.finishSelection()
        }
        model.start()

        quickPasteHotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: controlKey | optionKey) { [weak self] in
            self?.toggleQuickPaste()
        }
        if quickPasteHotKey == nil {
            NSLog("ClipShelf: couldn’t register ⌃⌥V; another app may already use it")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    // SwiftUI otherwise answers a relaunch by showing the empty Settings scene.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    // AppIcon.icns only exists in the app bundle, so `swift run` falls back to the SF symbol.
    private func menuBarIcon() -> NSImage? {
        if let icon = NSImage(named: "AppIcon")?.copy() as? NSImage {
            icon.size = NSSize(width: 20, height: 20)
            icon.accessibilityDescription = "ClipShelf clipboard history"
            return icon
        }
        let symbol = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipShelf clipboard history")
        symbol?.isTemplate = true
        return symbol
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

        // .transient misses clicks in other apps because we never become the active app.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.popover.performClose(nil)
            }
        }
    }

    private func toggleQuickPaste() {
        if popover.isShown {
            popover.performClose(nil)
        }
        quickPaste.toggle()
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
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
