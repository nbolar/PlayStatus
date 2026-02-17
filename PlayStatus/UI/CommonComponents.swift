import SwiftUI
import AppKit

struct ProviderBadge: View {
    let provider: NowPlayingProvider
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: provider.icon)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(provider.displayName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))

            Text("•").foregroundStyle(.secondary.opacity(0.6))

            Text(isPlaying ? "active" : "idle")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Controls

struct ControlsRow: View {
    let isPlaying: Bool
    let onPrev: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            GlassButton(systemName: "backward.fill", action: onPrev)
            GlassButton(systemName: isPlaying ? "pause.fill" : "play.fill", isPrimary: true, action: onPlayPause)
            GlassButton(systemName: "forward.fill", action: onNext)
        }
    }
}

struct OutputControlsRow: View {
    @ObservedObject var model: NowPlayingModel
    let showDeviceName: Bool

    private var selectedDeviceName: String {
        model.availableOutputDevices.first(where: { $0.id == model.selectedOutputDeviceID })?.name ?? "Output"
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                if model.availableOutputDevices.isEmpty {
                    Text("No output devices found")
                } else {
                    ForEach(model.availableOutputDevices) { device in
                        Button {
                            model.setOutputDevice(device.id)
                        } label: {
                            if device.id == model.selectedOutputDeviceID {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "hifispeaker.fill")
                        .font(.system(size: 10, weight: .semibold))
//                    if showDeviceName {
//                        Text(selectedDeviceName)
//                            .lineLimit(1)
//                            .truncationMode(.tail)
//                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: showDeviceName ? 168 : nil, alignment: .leading)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)

            Button {
                model.toggleOutputMute()
            } label: {
                Image(systemName: model.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
                    .foregroundStyle(model.outputMuted ? Color.secondary : Color.primary.opacity(0.9))
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { model.outputVolume },
                    set: { model.setOutputVolume($0) }
                ),
                in: 0...1
            )
            .frame(minWidth: 84, maxWidth: .infinity)
            .tint(.white.opacity(0.86))
            .opacity(model.outputMuted ? 0.55 : 1.0)
        }
        .onAppear {
            model.refreshAudioState()
        }
    }
}

struct GlassButton: View {
    let systemName: String
    var isPrimary: Bool = false
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: isPrimary ? 40 : 34, height: isPrimary ? 32 : 30)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(isPrimary ? 1.0 : 0.92))
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPrimary ? .ultraThinMaterial : .thinMaterial)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(isHovering ? 0.16 : 0.06), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.plusLighter)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(isPrimary ? 0.18 : 0.12), lineWidth: 1)
            }
        )
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isPressed)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Progress

struct ProgressBlock: View {
    let progress: Double
    let elapsed: Double
    let duration: Double
    let canSeek: Bool
    let onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let p = isDragging ? dragValue : progress

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule().fill(.white.opacity(0.35))
                        .frame(width: max(6, w * CGFloat(min(max(p, 0), 1))))
                        .blendMode(.screen)
                }
                .frame(height: 7)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard canSeek else { return }
                            isDragging = true
                            let x = min(max(0, value.location.x), w)
                            dragValue = Double(x / w)
                        }
                        .onEnded { _ in
                            guard canSeek else { return }
                            isDragging = false
                            onSeek(dragValue)
                        }
                )
            }
            .frame(height: 7)
            .opacity(canSeek ? 1.0 : 0.55)

            HStack {
                Text(formatTime(isDragging ? (duration * dragValue) : elapsed))
                    .monospacedDigit()
                    .frame(width: 42, alignment: .leading)
                Spacer()
                Text(formatTime(duration))
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    let image: NSImage?
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let outer = RoundedRectangle(cornerRadius: 22, style: .continuous)
            let inner = RoundedRectangle(cornerRadius: 18, style: .continuous)

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.34), .black.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 14)
                    .scaleEffect(0.92)
                    .opacity(0.9)

                outer
                    .fill(.ultraThinMaterial)
                    .overlay(outer.stroke(.white.opacity(0.22), lineWidth: 1.2))
                    .overlay(outer.stroke(tint.opacity(0.2), lineWidth: 1))

                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: side - 12, height: side - 12)
                            .background(tint.opacity(0.12))
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [.white.opacity(0.08), .black.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note")
                                .font(.system(size: 36, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary.opacity(0.95))
                        }
                        .frame(width: side - 12, height: side - 12)
                    }
                }
                .clipShape(inner, style: FillStyle(eoFill: false, antialiased: true))
                .overlay(inner.stroke(.white.opacity(0.1), lineWidth: 1))
                .overlay(
                    inner
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .clear, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                )
            }
            .frame(width: side, height: side)
            .clipped()
            .compositingGroup()
        }
        .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 10)
    }
}

// MARK: - Liquid Glass background/card

struct LiquidGlassBackground: View {
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.10), tint.opacity(0.06), tint.opacity(0.09)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.14), .clear],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 300
                    )
                )
                .blendMode(.screen)
                .opacity(0.50)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 8)
    }
}

struct LiquidGlassCard<Content: View>: View {
    let tint: Color
    let palette: [Color]
    @ViewBuilder var content: Content

    private var primary: Color { palette.first ?? tint }
    private var secondary: Color { palette.dropFirst().first ?? tint }
    private var tertiary: Color { palette.dropFirst(2).first ?? tint }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            primary.opacity(0.90),
                            secondary.opacity(0.84),
                            tertiary.opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.90)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .white.opacity(0.03), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)
                .opacity(0.26)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)

            content.padding(14)
        }
    }
}

struct RegularPopoverBackdrop: View {
    let tint: Color
    let palette: [Color]
    let artwork: NSImage?

    var body: some View {
        ZStack {
            tint.opacity(0.10)

            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .saturation(1.04)
                    .blur(radius: 52)
                    .scaleEffect(1.10)
                    .opacity(0.14)
            }
        }
    }
}

struct OuterCardBleedMask: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black)
                .padding(7)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}
