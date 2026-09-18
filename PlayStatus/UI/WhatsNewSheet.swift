import SwiftUI

/// The launch announcement: one release, said once, in the shape of Apple's own What's New
/// sheet.
///
/// It never tries to be the whole changelog. When more than one release is outstanding the
/// extras are summarised in a single line that hands off to `ReleaseLedgerView`, which is
/// the surface built for reading several releases in a row.
struct WhatsNewSheetView: View {
    let releases: [WhatsNewRelease]
    let currentVersion: String
    let onContinue: () -> Void
    let onOpenLedger: () -> Void

    private var headlineRelease: WhatsNewRelease? { releases.first }
    private var olderReleases: [WhatsNewRelease] { Array(releases.dropFirst()) }

    private var accents: [Color] {
        headlineRelease.map(WhatsNewPalette.accents(for:)) ?? [WhatsNewAccent.blue.color]
    }

    var body: some View {
        ZStack(alignment: .top) {
            WhatsNewAuroraBackdrop(accents: accents)

            VStack(spacing: 0) {
                header
                highlights
                Spacer(minLength: 0)
                olderReleasesLine
                footer
            }
        }
        .frame(width: WhatsNewSheetMetrics.width, height: WhatsNewSheetMetrics.height)
        .background(.background)
    }

    private var header: some View {
        VStack(spacing: 10) {
            WhatsNewAppIcon()

            WhatsNewPill(text: "Version \(headlineRelease?.displayVersion ?? currentVersion)", tint: nil)

            Text(headlineRelease?.headline ?? "You are up to date")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(headlineRelease?.summary ?? "There is nothing new to catch up on.")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 30)
        .padding(.horizontal, 34)
        .padding(.bottom, 22)
    }

    private var highlights: some View {
        WhatsNewScrollingList {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(headlineRelease?.highlights ?? []) { highlight in
                    WhatsNewHighlightRow(highlight: highlight, emphasis: .sheet)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var olderReleasesLine: some View {
        if let oldest = olderReleases.last {
            Button(action: onOpenLedger) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .semibold))

                    Text(olderReleasesSummary(oldest: oldest))
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 30)
                .padding(.bottom, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func olderReleasesSummary(oldest: WhatsNewRelease) -> String {
        let count = olderReleases.count
        let noun = count == 1 ? "release" : "releases"
        return "\(count) earlier \(noun) you haven't seen, back to \(oldest.displayVersion)"
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Release Notes…", action: onOpenLedger)
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .medium, design: .rounded))

            Spacer(minLength: 8)

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.4))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

enum WhatsNewSheetMetrics {
    static let width: CGFloat = 420
    static let height: CGFloat = 560
}
