import SwiftUI
import AppKit

enum DetailPaneVisualStyle {
    case mini
    case regular

    func foregroundStyle(for colorScheme: ColorScheme) -> AnyShapeStyle {
        if colorScheme == .dark {
            switch self {
            case .mini:
                return AnyShapeStyle(.white.opacity(0.86))
            case .regular:
                return AnyShapeStyle(.white.opacity(0.76))
            }
        }

        return AnyShapeStyle(Color.secondary.opacity(self == .mini ? 0.84 : 0.92))
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
    @Environment(\.colorScheme) private var colorScheme

    private var foregroundStyle: Color {
        if colorScheme == .dark {
            return .white.opacity(isSelected ? 0.96 : 0.66)
        }
        return isSelected ? .primary.opacity(0.90) : .secondary.opacity(0.88)
    }

    private var fillStyle: Color {
        if colorScheme == .dark {
            return .white.opacity(isSelected ? 0.16 : 0.08)
        }
        return .black.opacity(isSelected ? 0.075 : 0.035)
    }

    private var strokeStyle: Color {
        if colorScheme == .dark {
            return .white.opacity(isSelected ? 0.18 : 0.10)
        }
        return .black.opacity(isSelected ? 0.12 : 0.065)
    }

    var body: some View {
        Button(action: action) {
            Label(tab.displayName, systemImage: isSelected ? "\(tab.systemImage).fill" : tab.systemImage)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(foregroundStyle)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(fillStyle))
                .overlay(
                    Capsule()
                        .stroke(strokeStyle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DetailPaneSourceBadge: View {
    let text: String
    var emphasized: Bool = false
    var style: DetailPaneVisualStyle = .regular
    @Environment(\.colorScheme) private var colorScheme

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

    private var foregroundStyle: Color {
        if colorScheme == .dark {
            return .white.opacity(opacity)
        }
        return emphasized ? .primary.opacity(0.68) : .secondary.opacity(0.74)
    }

    private var fillStyle: Color {
        if colorScheme == .dark {
            return .white.opacity(fillOpacity)
        }
        return .black.opacity(emphasized ? 0.055 : 0.035)
    }

    private var strokeStyle: Color {
        if colorScheme == .dark {
            return .white.opacity(strokeOpacity)
        }
        return .black.opacity(emphasized ? 0.10 : 0.065)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(fillStyle))
            .overlay(Capsule().stroke(strokeStyle, lineWidth: 1))
    }
}

struct DetailPaneStateMessage: View {
    let message: String
    let icon: DetailPaneStateIcon
    var style: DetailPaneVisualStyle = .regular
    @Environment(\.colorScheme) private var colorScheme

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
            .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(.white.opacity(0.38)) : AnyShapeStyle(.tertiary))

            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(style.foregroundStyle(for: colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct CreditsPaneContent: View {
    let payload: CreditsPayload
    let style: CreditsPanePresentationStyle
    @Environment(\.colorScheme) private var colorScheme

    private var compactLabelStyle: Color {
        colorScheme == .dark ? .white.opacity(0.60) : .secondary.opacity(0.88)
    }

    private var compactValueStyle: Color {
        colorScheme == .dark ? .white.opacity(0.90) : .primary.opacity(0.88)
    }

    private var regularSectionStyle: Color {
        colorScheme == .dark ? .white.opacity(0.56) : .secondary.opacity(0.78)
    }

    private var regularLabelStyle: Color {
        colorScheme == .dark ? .white.opacity(0.64) : .secondary.opacity(0.92)
    }

    private var regularValueStyle: Color {
        colorScheme == .dark ? .white.opacity(0.90) : .primary.opacity(0.90)
    }

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
                        .foregroundStyle(compactLabelStyle)
                        .frame(width: 76, alignment: .leading)

                    Text(row.value)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(compactValueStyle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            if allRows.count > maxVisibleRows {
                Text("More credits available in regular view.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.46) : .secondary.opacity(0.72))
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
                        .foregroundStyle(regularSectionStyle)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(section.rows) { row in
                            HStack(alignment: .top, spacing: 12) {
                                Text(row.label)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(regularLabelStyle)
                                    .frame(width: 92, alignment: .leading)

                                Text(row.value)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(regularValueStyle)
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
