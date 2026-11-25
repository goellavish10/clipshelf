import AppKit
import Carbon.HIToolbox

@MainActor
enum TypingTarget {
    private static var hasPromptedForTrust = false

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestTrustOnce() {
        guard !isTrusted, !hasPromptedForTrust else { return }
        hasPromptedForTrust = true
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Text caret of the focused field in Cocoa screen coordinates, if the app exposes it.
    static func caretRect() -> NSRect? {
        guard isTrusted else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        // A hung app would otherwise block us for the default 6 seconds.
        AXUIElementSetMessagingTimeout(systemWide, 0.25)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focused as! AXUIElement

        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else {
            return nil
        }

        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &bounds
        ) == .success,
              let bounds,
              CFGetTypeID(bounds) == AXValueGetTypeID() else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect),
              rect.height > 0,
              rect.origin != .zero,
              let primaryScreen = NSScreen.screens.first else {
            return nil
        }

        return NSRect(
            x: rect.minX,
            y: primaryScreen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func paste() {
        guard isTrusted else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: isDown
            )
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
