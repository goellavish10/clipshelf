import AppKit

@MainActor
final class ClipboardMonitor {
    typealias ChangeHandler = (_ pasteboard: NSPasteboard, _ sourceApplication: NSRunningApplication?) -> Void

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let onChange: ChangeHandler
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?
    private(set) var isPaused = false

    init(
        pasteboard: NSPasteboard = .general,
        interval: TimeInterval = 0.45,
        onChange: @escaping ChangeHandler
    ) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.onChange = onChange
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        lastChangeCount = pasteboard.changeCount
    }

    func ignore(changeCount: Int) {
        ignoredChangeCount = changeCount
        lastChangeCount = changeCount
    }

    private func poll() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if ignoredChangeCount == currentChangeCount {
            ignoredChangeCount = nil
            return
        }

        guard !isPaused else { return }
        onChange(pasteboard, NSWorkspace.shared.frontmostApplication)
    }
}
