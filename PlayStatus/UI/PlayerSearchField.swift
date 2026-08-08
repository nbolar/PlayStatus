import SwiftUI
import AppKit

/// The player's search control: a glyph in the top-row cluster that expands into a field.
///
/// This lives in its own `View` type rather than as a `some View` helper on `NowPlayingPopover`
/// for a concrete reason. Once it moved inside the control cluster's `HStack`, alongside four
/// other control groups, the enclosing view's *static type* became large enough that resolving
/// it at runtime — `swift_getOpaqueTypeMetadataImpl` recursing through the mangled name —
/// overflowed the main thread's stack and killed the app with a `SIGSEGV` at the stack guard
/// page. A named struct gives the cluster a small concrete type and lets this subtree's own
/// metadata be resolved on its own, which keeps both sides well clear of that cliff.
struct PlayerSearchField: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    @FocusState.Binding var isFocused: Bool
    let provider: NowPlayingProvider
    let maxWidth: CGFloat
    var contrastBoost: Double = 0
    var controlScale: CGFloat = 1
    let onSubmit: () -> Void

    private var clampedContrast: Double { min(max(contrastBoost, 0), 1) }
    private var scale: CGFloat { min(max(controlScale, 0.80), 1.20) }

    private var placeholder: String {
        provider == .spotify ? "Search Spotify" : "Search Music library"
    }

    private var actionLabel: String {
        provider == .spotify ? "Open" : "Play"
    }

    private var fieldHeight: CGFloat { 26 * scale }
    /// Collapsed, it is one more glyph in the cluster and has to measure like one.
    private var collapsedWidth: CGFloat { 26 * scale }
    private var actionWidth: CGFloat { 58 * scale }
    private var spacing: CGFloat { 4 * scale }
    private var cornerRadius: CGFloat { 8 * scale }

    private var expandedFieldWidth: CGFloat {
        max(140, max(180, maxWidth) - actionWidth - spacing)
    }

    private var containerWidth: CGFloat {
        isExpanded ? expandedFieldWidth : collapsedWidth
    }

    private var textFieldWidth: CGFloat {
        max(0, expandedFieldWidth - (40 * scale))
    }

    private var queryIsEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let spring = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)

    var body: some View {
        HStack(spacing: spacing) {
            fieldGroup
            actionButton
        }
        .frame(height: fieldHeight)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchSectionFramePreferenceKey.self,
                    value: isExpanded ? proxy.frame(in: .named("popoverRoot")) : .zero
                )
            }
        )
        .onChange(of: isFocused) { _, focused in
            if !focused, queryIsEmpty {
                withAnimation(spring) { isExpanded = false }
            }
        }
    }

    private var fieldGroup: some View {
        HStack(spacing: isExpanded ? (6 * scale) : 0) {
            toggleButton
            field
        }
        .padding(.horizontal, isExpanded ? (8 * scale) : 0)
        .frame(width: containerWidth, height: fieldHeight, alignment: isExpanded ? .leading : .center)
        // Bare like the rest of the cluster until it opens; the field only earns a surface
        // once there is something to type into.
        .background(fieldBackground)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            guard !isExpanded else { return }
            expand()
        }
    }

    private var toggleButton: some View {
        Button {
            if isExpanded, queryIsEmpty {
                withAnimation(spring) { isExpanded = false }
                isFocused = false
            } else if !isExpanded {
                expand()
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13 * scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 18 * scale, height: 18 * scale)
        }
        .buttonStyle(.plain)
        .frame(
            width: isExpanded ? (18 * scale) : collapsedWidth,
            height: fieldHeight,
            alignment: .center
        )
        .contentShape(Rectangle())
        .accessibilityLabel(Text(isExpanded ? "Close search" : "Search"))
    }

    private var field: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12 * scale, weight: .medium))
            .foregroundStyle(.white.opacity(0.94))
            .focused($isFocused)
            .onSubmit(onSubmit)
            .frame(width: isExpanded ? textFieldWidth : 0, alignment: .leading)
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(isExpanded)
    }

    private var fieldBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(min(0.30, 0.10 + (0.14 * clampedContrast))))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.10 * clampedContrast))
        }
        .opacity(isExpanded ? 1 : 0)
    }

    /// Quiet enough to sit next to bare glyphs. As a prominent bordered button this was the
    /// heaviest thing on the surface, for the least-used action on it.
    private var actionButton: some View {
        Button(action: onSubmit) {
            Text(actionLabel)
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: actionWidth, height: fieldHeight)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(min(0.88, 0.44 + (0.34 * clampedContrast))))
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: isExpanded ? actionWidth : 0)
        .opacity(isExpanded ? 1 : 0)
        .scaleEffect(isExpanded ? 1 : 0.95)
        .allowsHitTesting(isExpanded)
        .clipped()
        .disabled(queryIsEmpty)
    }

    private func expand() {
        withAnimation(spring) { isExpanded = true }
        isFocused = true
    }
}
