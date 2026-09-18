import SwiftUI
import AppKit
import Combine

/// Owns the two What's New surfaces: the launch sheet and the release ledger.
///
/// `OnboardingCoordinator` still owns what counts as seen and what the walkthrough does;
/// this only owns windows. On an upgrade launch the sheet replaces the walkthrough; the
/// tour is still available from the app menu and Settings, it just no longer opens uninvited.
@MainActor
final class WhatsNewCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = WhatsNewCoordinator()

    private var sheetWindow: NSWindow?
    /// A hosting *view*, not a controller: the sheet's backdrop has to run under the title
    /// bar, and a hosting controller insists on driving the window's content size from the
    /// view's fitting size, which re-adds a title bar's height to the frame.
    private var sheetHost: NSHostingView<AnyView>?
    private static let ledgerFrameAutosaveName = NSWindow.FrameAutosaveName("PlayStatusReleaseLedgerWindow")
    private var ledgerWindow: NSWindow?
    private var ledgerHost: NSHostingView<AnyView>?
    /// Set while we are closing a window ourselves, so `windowWillClose` can tell a
    /// programmatic dismissal apart from the user hitting the red button.
    private var isClosingWindow = false
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        NowPlayingModel.shared.$appearanceRevision
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyAppearanceOverride()
            }
            .store(in: &cancellables)
    }

    private var currentVersionString: String {
        OnboardingCoordinator.currentAppRelease?.description
            ?? WhatsNewCatalog.latest?.displayVersion
            ?? ""
    }

    // MARK: - Sheet

    /// Show the announcement for whatever this machine has not been told about yet.
    ///
    /// Closing it — by any route, including the red button — is what marks those releases
    /// seen, which mirrors how the walkthrough has always behaved.
    func presentSheet(releases: [WhatsNewRelease]) {
        guard !releases.isEmpty else { return }

        let window = ensureSheetWindow()
        sheetHost?.rootView = AnyView(
            WhatsNewSheetView(
                releases: releases,
                currentVersion: currentVersionString,
                onContinue: { [weak self] in self?.dismissSheet() },
                onOpenLedger: { [weak self] in self?.presentLedger() }
            )
        )
        applyAppearanceOverride()

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// The replay entry point: show the release this build actually is, even when there is
    /// nothing outstanding.
    func presentSheetForCurrentRelease() {
        presentSheet(releases: OnboardingCoordinator.shared.releasesForWhatsNew)
    }

    private func dismissSheet() {
        OnboardingCoordinator.shared.markReleasesSeen()
        guard let sheetWindow else { return }
        isClosingWindow = true
        sheetWindow.close()
        isClosingWindow = false
        self.sheetWindow = nil
        sheetHost = nil
    }

    private func ensureSheetWindow() -> NSWindow {
        if let sheetWindow { return sheetWindow }

        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.wantsLayer = true
        // The backdrop is meant to run under the title bar. Left alone, SwiftUI insets the
        // content by the title bar's height *and* reports that inset in its fitting size,
        // which both drops the aurora below the traffic lights and grows the window by 32pt.
        host.safeAreaRegions = []
        sheetHost = host

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: WhatsNewSheetMetrics.width,
                height: WhatsNewSheetMetrics.height
            ),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = "What's New in PlayStatus"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(
            NSSize(width: WhatsNewSheetMetrics.width, height: WhatsNewSheetMetrics.height)
        )
        window.center()
        sheetWindow = window
        return window
    }

    // MARK: - Ledger

    /// The archive. Opened from the sheet or from the app menu; unlike the sheet, closing it
    /// changes nothing — reading is not the same as dismissing.
    func presentLedger() {
        let window = ensureLedgerWindow()
        let unseen = Set(OnboardingCoordinator.shared.unseenReleases.map(\.id))
        ledgerHost?.rootView = AnyView(
            ReleaseLedgerView(
                releases: WhatsNewCatalog.releases.reversed(),
                unseenVersions: unseen,
                currentVersion: currentVersionString,
                onMarkAllRead: { OnboardingCoordinator.shared.markReleasesSeen() },
                onClose: { [weak self] in self?.closeLedger() }
            )
        )
        applyAppearanceOverride()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closeLedger() {
        guard let ledgerWindow else { return }
        isClosingWindow = true
        ledgerWindow.close()
        isClosingWindow = false
        self.ledgerWindow = nil
        ledgerHost = nil
    }

    private func ensureLedgerWindow() -> NSWindow {
        if let ledgerWindow { return ledgerWindow }

        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.wantsLayer = true
        ledgerHost = host

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ReleaseLedgerMetrics.width,
                height: ReleaseLedgerMetrics.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = "What's New"
        window.minSize = NSSize(
            width: ReleaseLedgerMetrics.minWidth,
            height: ReleaseLedgerMetrics.minHeight
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        // The view only states its minimum; without this the window opens at that minimum
        // rather than at the size the ledger was designed for.
        window.setContentSize(
            NSSize(width: ReleaseLedgerMetrics.width, height: ReleaseLedgerMetrics.height)
        )
        // Restore before registering, so there is an answer to whether anything was stored.
        // Centring unconditionally after `setFrameAutosaveName` — which restores the saved
        // frame itself — threw that position away again on every open, and the ledger always
        // came back in the middle of the screen however the user had left it.
        let restoredSavedFrame = window.setFrameUsingName(Self.ledgerFrameAutosaveName)
        window.setFrameAutosaveName(Self.ledgerFrameAutosaveName)
        if !restoredSavedFrame { window.center() }
        ledgerWindow = window
        return window
    }

    // MARK: - Shared

    private func applyAppearanceOverride() {
        let appearance = NowPlayingModel.shared.appAppearanceMode.nsAppearance
        for window in [sheetWindow, ledgerWindow] {
            window?.appearance = appearance
            window?.contentView?.appearance = appearance
        }
        sheetHost?.appearance = appearance
        ledgerHost?.appearance = appearance
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === sheetWindow {
            sheetWindow = nil
            sheetHost = nil
            // Closing the announcement is consent to never see it again, however it closed.
            if !isClosingWindow {
                OnboardingCoordinator.shared.markReleasesSeen()
            }
            return
        }

        if window === ledgerWindow {
            ledgerWindow = nil
            ledgerHost = nil
        }
    }
}
