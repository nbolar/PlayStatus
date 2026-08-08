import AppKit
import SwiftUI

/// Keyboard control for the open player.
///
/// The app has global hotkeys, but with the player actually in front of you no key did
/// anything — including the one everybody tries first. This is a local event monitor rather
/// than SwiftUI `.onKeyPress` because the surface is an `NSPopover` whose content view is not
/// reliably the focused responder, and because the same bindings have to serve the detached
/// window.
///
/// Two rules keep it from stealing keys it has no business taking:
/// the surface must be the key window, and a text field being edited wins every key except
/// Escape — otherwise typing "m" into search would flip the player into mini mode.
@MainActor
final class PlayerKeyboardCommands {
    private let model: NowPlayingModel
    /// The window the player is currently presented in, or nil when it is not on screen.
    private let surfaceWindow: () -> NSWindow?
    private let closeSurface: () -> Void
    private var monitor: Any?

    private let seekStep: Double = 10
    private let volumeStep: Double = 0.05

    init(
        model: NowPlayingModel,
        surfaceWindow: @escaping () -> NSWindow?,
        closeSurface: @escaping () -> Void
    ) {
        self.model = model
        self.surfaceWindow = surfaceWindow
        self.closeSurface = closeSurface
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handle(event) }
        }
    }

    func remove() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    /// Returns nil to consume the event, or the event to let it continue to the responder
    /// chain.
    private func handle(_ event: NSEvent) -> NSEvent? {
        // A local monitor only sees events already delivered to this app, so receiving one is
        // itself the proof that we have focus. Requiring the surface to be `isKeyWindow` was
        // too strict: an `NSPopover` shown from a status item in an accessory app does not
        // reliably take key status until you click into it, so ⌘F did nothing on a popover you
        // had merely opened.
        guard model.isPopoverVisible, let surface = surfaceWindow() else { return event }

        // Another of our own windows has focus — Settings, the walkthrough — so it owns the
        // keyboard and these bindings must stay out of its way.
        if let keyWindow = NSApp.keyWindow, keyWindow !== surface { return event }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isEditingText = isEditing(surface.firstResponder)
            || isEditing(NSApp.keyWindow?.firstResponder)

        // Escape unwinds one level at a time. It has to be consumed here rather than passed
        // through, because `NSPopover` closes the whole surface on Escape before the focused
        // field ever sees it — so mid-search, one keystroke used to dismiss everything.
        if event.keyCode == 53 {
            if model.searchFieldIsOpen {
                model.requestSearchDismiss()
                return nil
            }
            closeSurface()
            return nil
        }

        if modifiers.contains(.command) {
            // ⌘F opens the search field wherever focus currently is.
            if event.charactersIgnoringModifiers?.lowercased() == "f",
               model.resolvedSearchProvider != .none {
                #if DEBUG
                NSLog("PlayStatus keyboard: cmd-F accepted (mini=%@)", model.miniMode ? "yes" : "no")
                #endif
                model.requestSearchFocus()
                return nil
            }
            return event
        }

        guard !isEditingText else { return event }

        switch event.keyCode {
        case 49: // space
            guard model.canControlPlayback else { return nil }
            model.playPause()
            return nil
        case 123: // left arrow
            if modifiers.contains(.option) {
                guard model.canControlPlayback else { return nil }
                model.previousTrack()
            } else {
                seek(by: -seekStep)
            }
            return nil
        case 124: // right arrow
            if modifiers.contains(.option) {
                guard model.canControlPlayback else { return nil }
                model.nextTrack()
            } else {
                seek(by: seekStep)
            }
            return nil
        case 126: // up arrow
            adjustVolume(by: volumeStep)
            return nil
        case 125: // down arrow
            adjustVolume(by: -volumeStep)
            return nil
        default:
            break
        }

        guard modifiers.isEmpty || modifiers == .shift else { return event }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "l":
            toggleDetails(.lyrics)
            return nil
        case "c":
            toggleDetails(.credits)
            return nil
        case "h":
            toggleDetails(.history)
            return nil
        case "m":
            model.miniMode.toggle()
            return nil
        default:
            return event
        }
    }

    /// A field being edited owns the keyboard. Both cases matter: SwiftUI's `TextField`
    /// installs a field editor (`NSTextView`) as first responder, but an `NSTextField` can
    /// hold it briefly while focus is changing hands.
    private func isEditing(_ responder: NSResponder?) -> Bool {
        switch responder {
        case is NSTextView, is NSTextField:
            return true
        default:
            return false
        }
    }

    private func seek(by seconds: Double) {
        let duration = model.duration
        guard model.canSeek, duration > 0 else { return }
        let target = min(max(model.elapsed + seconds, 0), duration)
        model.seek(to: target / duration)
    }

    private func adjustVolume(by delta: Double) {
        model.setOutputVolume(min(max(model.outputVolume + delta, 0), 1))
    }

    /// Routes to whichever pane the current mode actually owns.
    private func toggleDetails(_ tab: DetailsPaneTab) {
        if model.miniMode {
            model.toggleMiniDetailsTab(tab)
        } else {
            model.toggleRegularDetailsTab(tab)
        }
    }
}
