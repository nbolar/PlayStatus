import AppKit
import SwiftUI

/// Keeps popover sizing in AppKit. Installing the hosting controller directly on
/// NSPopover lets NSHostingView's window layout callback resize the popover again
/// during layout, even with sizingOptions empty (macOS 26 stack-overflow reports).
/// The plain root view is the sizing boundary; SwiftUI only follows its bounds.
@MainActor
final class PopoverContentController: NSViewController {
    let hostingView: NSHostingView<AnyView>

    var rootView: AnyView {
        get { hostingView.rootView }
        set { hostingView.rootView = newValue }
    }

    init(rootView: AnyView) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        hostingView.sizingOptions = []
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let container = NSView()
        view = container

        // Use a hosting view, not a child hosting controller: the latter still
        // forwards preferredContentSize changes through a plain parent controller.
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = container.bounds
        container.addSubview(hostingView)
    }
}
