import SwiftUI
import AppKit

struct DetachedWindowDragLockBridge: NSViewRepresentable {
    let locked: Bool

    func makeNSView(context: Context) -> DetachedWindowDragLockView {
        let view = DetachedWindowDragLockView()
        view.setLocked(locked)
        return view
    }

    func updateNSView(_ nsView: DetachedWindowDragLockView, context: Context) {
        nsView.setLocked(locked)
    }
}

final class DetachedWindowDragLockView: NSView {
    private weak var trackedWindow: DetachedNowPlayingWindow?
    private var isLocked = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setLocked(isLocked)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow {
            releaseTrackedWindowIfNeeded()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func setLocked(_ locked: Bool) {
        isLocked = locked

        guard let detachedWindow = window as? DetachedNowPlayingWindow else {
            releaseTrackedWindowIfNeeded()
            return
        }

        if locked {
            trackedWindow = detachedWindow
            detachedWindow.isMovableByWindowBackground = false
        } else {
            releaseTrackedWindowIfNeeded()
        }
    }

    deinit {
        releaseTrackedWindowIfNeeded()
    }

    private func releaseTrackedWindowIfNeeded() {
        guard let trackedWindow else { return }
        trackedWindow.isMovableByWindowBackground = true
        self.trackedWindow = nil
    }
}
