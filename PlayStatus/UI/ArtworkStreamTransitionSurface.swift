import SwiftUI
import AppKit

struct ArtworkStreamTransitionSurface<StaticContent: View>: View {
    let image: NSImage?
    let animatedArtworkURL: URL?
    let isActive: Bool
    var transitionKeyPrefix: String = ""
    var transitionAnimationsEnabled: Bool = true
    var animateOnFirstAppear: Bool = true
    @ViewBuilder let staticContent: () -> StaticContent

    @State private var streamReadyForDisplay = false

    private let streamCrossfadeDuration: Double = 2.8

    private var artworkTransitionKey: String {
        let baseKey: String
        if let image {
            baseKey = "art:\(image.artworkTransitionIdentity)"
        } else if let animatedArtworkURL {
            baseKey = "animated:\(animatedArtworkURL.absoluteString)"
        } else {
            baseKey = "art:none"
        }

        guard !transitionKeyPrefix.isEmpty else { return baseKey }
        return "\(transitionKeyPrefix)|\(baseKey)"
    }

    private var hasArtworkContent: Bool {
        image != nil || animatedArtworkURL != nil
    }

    private var streamCrossfadeAnimation: Animation {
        .easeInOut(duration: streamCrossfadeDuration)
    }

    var body: some View {
        ZStack {
            staticContent()

            if let animatedArtworkURL {
                AnimatedArtworkPlayerView(
                    streamURL: animatedArtworkURL,
                    isActive: isActive,
                    onRenderReadinessChanged: { isReady in
                        guard isReady != streamReadyForDisplay else { return }
                        withAnimation(streamCrossfadeAnimation) {
                            streamReadyForDisplay = isReady
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(streamReadyForDisplay ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .artworkTransitionFade(
            animationKey: artworkTransitionKey,
            isEnabled: transitionAnimationsEnabled,
            hasContent: hasArtworkContent,
            animateOnFirstAppear: animateOnFirstAppear
        )
        .onChange(of: animatedArtworkURL) { _, _ in
            withAnimation(streamCrossfadeAnimation) {
                streamReadyForDisplay = false
            }
        }
    }
}
