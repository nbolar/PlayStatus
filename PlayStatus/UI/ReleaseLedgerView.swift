import SwiftUI

/// Every release in the catalog, browsable.
///
/// The sheet announces one release; this is where the rest live. It is also what someone
/// upgrading from several versions back actually needs — a list they can walk at their own
/// pace rather than a wall of six releases in one scroll.
struct ReleaseLedgerView: View {
    /// Newest first, which is the order the sidebar reads in.
    let releases: [WhatsNewRelease]
    let currentVersion: String
    let onMarkAllRead: () -> Void
    let onClose: () -> Void

    /// Snapshotted when the window opens so the dots do not disappear out from under
    /// someone who is still reading the release they mark as seen by reading it.
    @State private var unseenVersions: Set<String>
    @State private var selectedVersion: String

    init(
        releases: [WhatsNewRelease],
        unseenVersions: Set<String>,
        currentVersion: String,
        onMarkAllRead: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.releases = releases
        self.currentVersion = currentVersion
        self.onMarkAllRead = onMarkAllRead
        self.onClose = onClose
        _unseenVersions = State(initialValue: unseenVersions)
        let firstUnseen = releases.first { unseenVersions.contains($0.id) }
        _selectedVersion = State(initialValue: firstUnseen?.id ?? releases.first?.id ?? "")
    }

    private var unseenReleases: [WhatsNewRelease] {
        releases.filter { unseenVersions.contains($0.id) }
    }

    private var earlierReleases: [WhatsNewRelease] {
        releases.filter { !unseenVersions.contains($0.id) }
    }

    /// The running build can carry a pre-release suffix (`3.1.1-beta2`) while the catalog
    /// entry it belongs to is plain `3.1.1`, so the two are compared by release line.
    private func isCurrentRelease(_ release: WhatsNewRelease) -> Bool {
        ReleaseVersion(currentVersion)?.releaseLine == release.version
    }

    private var selectedRelease: WhatsNewRelease? {
        releases.first { $0.id == selectedVersion }
    }

    /// The release below the selected one, which is what "Next" means in a list that runs
    /// newest to oldest.
    private var nextRelease: WhatsNewRelease? {
        guard let index = releases.firstIndex(where: { $0.id == selectedVersion }) else { return nil }
        let next = index + 1
        return next < releases.count ? releases[next] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail
            }
            footer
        }
        .frame(minWidth: ReleaseLedgerMetrics.minWidth, minHeight: ReleaseLedgerMetrics.minHeight)
        .background(.background)
    }

    private var sidebar: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2) {
                if !unseenReleases.isEmpty {
                    sidebarLabel("Since you last opened")
                    ForEach(unseenReleases) { release in
                        sidebarRow(release, isUnseen: true)
                    }
                }

                if !earlierReleases.isEmpty {
                    sidebarLabel(unseenReleases.isEmpty ? "All releases" : "Earlier")
                        .padding(.top, unseenReleases.isEmpty ? 0 : 10)
                    ForEach(earlierReleases) { release in
                        sidebarRow(release, isUnseen: false)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .frame(width: ReleaseLedgerMetrics.sidebarWidth)
        .background(.quaternary.opacity(0.28))
    }

    private func sidebarLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func sidebarRow(_ release: WhatsNewRelease, isUnseen: Bool) -> some View {
        let isSelected = release.id == selectedVersion

        return Button {
            selectedVersion = release.id
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(isUnseen ? WhatsNewAccent.green.color : .clear)
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(release.displayVersion)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    Text(release.headline)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.selection.opacity(0.5)) : AnyShapeStyle(.clear))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var detail: some View {
        if let release = selectedRelease {
            WhatsNewScrollingList {
                VStack(alignment: .leading, spacing: 0) {
                    detailHeader(release)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(release.highlights) { highlight in
                            WhatsNewHighlightRow(highlight: highlight, emphasis: .ledger)
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 22)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            // A fresh list per release: each one opens at its top, and its More pill answers
            // for its own length rather than for wherever the previous release was scrolled.
            .id(release.id)
        } else {
            Text("Select a release")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(_ release: WhatsNewRelease) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isCurrentRelease(release) {
                    WhatsNewPill(text: "\(release.displayVersion) · This update", tint: WhatsNewAccent.green.color)
                } else {
                    WhatsNewPill(text: release.displayVersion, tint: nil)
                }

                WhatsNewPill(
                    text: release.highlights.count == 1 ? "1 change" : "\(release.highlights.count) changes",
                    tint: nil
                )
            }

            Text(release.headline)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            Text(release.summary)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Mark All as Read") {
                unseenVersions.removeAll()
                onMarkAllRead()
            }
            .buttonStyle(.link)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .disabled(unseenVersions.isEmpty)

            Spacer(minLength: 8)

            Button("Close", action: onClose)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

            Button("Next Release") {
                guard let next = nextRelease else { return }
                selectedVersion = next.id
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(nextRelease == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.4))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

enum ReleaseLedgerMetrics {
    static let sidebarWidth: CGFloat = 212
    static let width: CGFloat = 760
    static let height: CGFloat = 470
    static let minWidth: CGFloat = 680
    static let minHeight: CGFloat = 420
}
