import SwiftUI
import AppKit

enum DetailPaneVisualStyle {
    case mini
    case regular

    var foregroundOpacity: Double {
        switch self {
        case .mini:
            return 0.86
        case .regular:
            return 1.0
        }
    }

    var foregroundStyle: AnyShapeStyle {
        switch self {
        case .mini:
            return AnyShapeStyle(.white.opacity(foregroundOpacity))
        case .regular:
            return AnyShapeStyle(.secondary)
        }
    }
}

enum DetailPaneStateIcon {
    case sfSymbol(String)
    case provider(ProviderIconKind)
}

enum CreditsPanePresentationStyle {
    case compact(maxVisibleRows: Int)
    case regular
}

struct DetailPaneTabChip: View {
    let tab: DetailsPaneTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(tab.displayName, systemImage: isSelected ? "\(tab.systemImage).fill" : tab.systemImage)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.66))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(isSelected ? 0.16 : 0.08)))
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(isSelected ? 0.18 : 0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DetailPaneSourceBadge: View {
    let text: String
    var emphasized: Bool = false
    var style: DetailPaneVisualStyle = .regular

    private var opacity: Double {
        switch style {
        case .mini:
            return emphasized ? 0.58 : 0.46
        case .regular:
            return emphasized ? 0.58 : 0.50
        }
    }

    private var fillOpacity: Double {
        emphasized ? 0.10 : 0.08
    }

    private var strokeOpacity: Double {
        emphasized ? 0.14 : 0.10
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(opacity))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(fillOpacity)))
            .overlay(Capsule().stroke(.white.opacity(strokeOpacity), lineWidth: 1))
    }
}

struct DetailPaneStateMessage: View {
    let message: String
    let icon: DetailPaneStateIcon
    var style: DetailPaneVisualStyle = .regular

    var body: some View {
        VStack(spacing: 8) {
            Group {
                switch icon {
                case .sfSymbol(let symbolName):
                    Image(systemName: symbolName)
                        .font(.system(size: 22, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                case .provider(let providerIcon):
                    ProviderIconView(icon: providerIcon, size: 22, weight: .regular)
                }
            }
            .foregroundStyle(.tertiary)

            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(style.foregroundStyle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct CreditsPaneContent: View {
    let payload: CreditsPayload
    let style: CreditsPanePresentationStyle

    var body: some View {
        ScrollView(.vertical) {
            switch style {
            case .compact(let maxVisibleRows):
                compactContent(maxVisibleRows: maxVisibleRows)
            case .regular:
                regularContent
            }
        }
        .scrollIndicators(.hidden)
    }

    private var allRows: [CreditsRow] {
        payload.sections.flatMap(\.rows)
    }

    private func compactContent(maxVisibleRows: Int) -> some View {
        let visibleRows = Array(allRows.prefix(maxVisibleRows))

        return LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(visibleRows) { row in
                HStack(alignment: .top, spacing: 10) {
                    Text(row.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))
                        .frame(width: 76, alignment: .leading)

                    Text(row.value)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.90))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            if allRows.count > maxVisibleRows {
                Text("More credits available in regular view.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private var regularContent: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(payload.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(section.rows) { row in
                            HStack(alignment: .top, spacing: 12) {
                                Text(row.label)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.64))
                                    .frame(width: 92, alignment: .leading)

                                Text(row.value)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.90))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

func openLRCLibWebsite() {
    guard let url = URL(string: "https://lrclib.net") else { return }
    NSWorkspace.shared.open(url)
}
