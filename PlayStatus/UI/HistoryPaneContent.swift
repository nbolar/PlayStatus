import SwiftUI
import AppKit
import Combine

/// Loads history row thumbnails out of the media cache.
///
/// Rows are recycled as the list scrolls, so each lookup is keyed and cached in memory here;
/// the actor round trip happens once per track, not once per appearance. A miss — an evicted
/// thumbnail, or a play recorded with no artwork on screen — resolves to nil and the row falls
/// back to its provider glyph.
@MainActor
final class HistoryArtworkProvider: ObservableObject {
    static let shared = HistoryArtworkProvider()

    @Published private(set) var images: [String: NSImage] = [:]
    private var misses: Set<String> = []
    private var inflight: Set<String> = []

    private init() {}

    func image(forKey key: String) -> NSImage? {
        images[key]
    }

    func loadIfNeeded(key: String) {
        guard !key.isEmpty else { return }
        guard images[key] == nil, !misses.contains(key), !inflight.contains(key) else { return }
        inflight.insert(key)

        Task {
            let data = await PersistentMediaCache.shared.fetchArtworkData(forKey: key)
            let image = data.flatMap { NSImage(data: $0) }
            self.inflight.remove(key)
            if let image {
                self.images[key] = image
            } else {
                self.misses.insert(key)
            }
        }
    }

    /// Called when history is cleared, so a later play that reuses a key cannot serve a
    /// thumbnail from a record the user deleted.
    func reset() {
        images.removeAll()
        misses.removeAll()
    }
}

enum HistoryPanePresentationStyle {
    case compact
    case regular

    var rowSpacing: CGFloat {
        switch self {
        case .compact: return 6
        case .regular: return 8
        }
    }

    var artworkSide: CGFloat {
        switch self {
        case .compact: return 26
        case .regular: return 34
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .compact: return 11.5
        case .regular: return 12.5
        }
    }

    var subtitleSize: CGFloat {
        switch self {
        case .compact: return 10.5
        case .regular: return 11.5
        }
    }
}

struct HistoryPaneContent: View {
    let entries: [PlayHistoryEntry]
    let style: HistoryPanePresentationStyle
    var tint: Color = .accentColor
    /// Plays per `collapseIdentity`. Rows show a repeat count instead of repeating, so
    /// collapsing the list does not throw the information away.
    var playCounts: [String: Int] = [:]
    let onReplay: (PlayHistoryEntry) -> Void
    let onRemove: (PlayHistoryEntry) -> Void

    /// Ceiling on rendered rows, matching `RegularLyricsScrollContent`'s cap. The store keeps
    /// thousands; a details pane never needs to lay out more than a session's worth.
    private let maxRenderableRows = 300

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: style.rowSpacing) {
                ForEach(groupedEntries, id: \.key) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            HistoryRow(
                                entry: entry,
                                style: style,
                                tint: tint,
                                playCount: playCounts[entry.collapseIdentity] ?? 1,
                                onReplay: { onReplay(entry) },
                                onRemove: { onRemove(entry) }
                            )
                        }
                    } header: {
                        HistoryDayHeader(title: group.key, style: style)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private struct DayGroup {
        let key: String
        let entries: [PlayHistoryEntry]
    }

    private var groupedEntries: [DayGroup] {
        let visible = Array(entries.prefix(maxRenderableRows))
        var order: [String] = []
        var buckets: [String: [PlayHistoryEntry]] = [:]

        for entry in visible {
            let key = Self.dayLabel(for: entry.playedAt)
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(entry)
        }

        return order.map { DayGroup(key: $0, entries: buckets[$0] ?? []) }
    }

    private static func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return formatter
    }()
}

private struct HistoryDayHeader: View {
    let title: String
    let style: HistoryPanePresentationStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.system(size: style == .compact ? 9.5 : 11, weight: .semibold, design: .rounded))
            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.46) : .secondary.opacity(0.78))
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

private struct HistoryRow: View {
    let entry: PlayHistoryEntry
    let style: HistoryPanePresentationStyle
    let tint: Color
    let playCount: Int
    let onReplay: () -> Void
    let onRemove: () -> Void

    @ObservedObject private var artwork = HistoryArtworkProvider.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var titleStyle: Color {
        colorScheme == .dark ? .white.opacity(0.92) : .primary.opacity(0.90)
    }

    private var subtitleStyle: Color {
        colorScheme == .dark ? .white.opacity(0.56) : .secondary.opacity(0.86)
    }

    private var timestampStyle: Color {
        colorScheme == .dark ? .white.opacity(0.40) : .secondary.opacity(0.68)
    }

    var body: some View {
        Button(action: onReplay) {
            HStack(spacing: 10) {
                thumbnail

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.displayTitle)
                        .font(.system(size: style.titleSize, weight: .semibold))
                        .foregroundStyle(titleStyle)
                        .lineLimit(1)

                    Text(entry.displaySubtitle)
                        .font(.system(size: style.subtitleSize, weight: .medium))
                        .foregroundStyle(subtitleStyle)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if playCount > 1 {
                    Text("×\(playCount)")
                        .font(.system(size: style.subtitleSize - 0.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(timestampStyle)
                        .monospacedDigit()
                        .help("Played \(playCount) times")
                }

                if !entry.completed {
                    // A skip is worth marking but not worth a word: the glyph reads at a
                    // glance and costs no width in an already narrow row.
                    Image(systemName: "forward.end")
                        .font(.system(size: style.subtitleSize - 1, weight: .semibold))
                        .foregroundStyle(timestampStyle)
                        .help("Skipped")
                }

                Text(Self.relativeLabel(for: entry.playedAt))
                    .font(.system(size: style.subtitleSize - 0.5, weight: .medium, design: .rounded))
                    .foregroundStyle(timestampStyle)
                    .monospacedDigit()
            }
            .padding(.vertical, style == .compact ? 3 : 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering
                          ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                          : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering }
        }
        .help("Play \(entry.displayTitle) again")
        .accessibilityLabel(Text(accessibilityLabel))
        .contextMenu {
            Button("Play Again", action: onReplay)
            Button("Copy Title and Artist") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("\(entry.track.title) — \(entry.track.artist)", forType: .string)
            }
            Divider()
            Button("Remove from History", action: onRemove)
        }
        .onAppear { artwork.loadIfNeeded(key: entry.artworkKey) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        let side = style.artworkSide
        Group {
            if let image = artwork.image(forKey: entry.artworkKey) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                    ProviderIconView(icon: entry.provider.iconKind, size: side * 0.46, weight: .regular)
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.34) : .secondary.opacity(0.56))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var accessibilityLabel: String {
        var parts = [entry.displayTitle, entry.displaySubtitle, Self.relativeLabel(for: entry.playedAt)]
        if playCount > 1 { parts.append("Played \(playCount) times") }
        if !entry.completed { parts.append("Skipped") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private static func relativeLabel(for date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3600))h" }
        return timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter
    }()
}
