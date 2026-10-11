import CardCore
import CardFX
import SwiftUI

/// Draws a `CardArtwork`: asset images synchronously, URLs through
/// `ArtworkLoader` with a shimmer placeholder while loading. The load is a
/// structured task tied to the view, cancelled when the view disappears or
/// when the URL changes.
public struct ArtworkView: View {
    public var artwork: CardArtwork
    public var contentMode: ContentMode
    public var maxPixelSize: Int

    @State private var loaded: CGImage?
    @State private var failed = false

    public init(_ artwork: CardArtwork, contentMode: ContentMode = .fill, maxPixelSize: Int = 1024) {
        self.artwork = artwork
        self.contentMode = contentMode
        self.maxPixelSize = maxPixelSize
        // An asset decoded earlier is drawn on the first frame: no blank
        // cover while the pack flies in from the carousel.
        if let ready = Self.readyImage(for: artwork, maxPixelSize: maxPixelSize) {
            _loaded = State(initialValue: ready)
        }
    }

    private static func readyImage(for artwork: CardArtwork, maxPixelSize: Int) -> CGImage? {
        guard case .asset(let name) = artwork else { return nil }
        return ArtworkLoader.readyImage(forAsset: name, maxPixelSize: maxPixelSize)
    }

    public var body: some View {
        switch artwork {
        case .asset, .url:
            loaded(artwork)
        case .none:
            proceduralPlaceholder
        }
    }

    /// Both sources decode in `ArtworkLoader`, off the main actor and
    /// downsampled, so a card never decodes a full-size image at draw time.
    @ViewBuilder
    private func loaded(_ artwork: CardArtwork) -> some View {
        ZStack {
            if let loaded {
                Image(decorative: loaded, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                proceduralPlaceholder
                    .overlay {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.7))
                    }
            } else {
                // Cached assets resolve within a frame; only remote images
                // stay long enough to deserve the shimmer.
                if case .url = artwork {
                    LoadingPlaceholder()
                } else {
                    Color.clear
                }
            }
        }
        .task(id: artwork) {
            failed = false
            if let ready = Self.readyImage(for: artwork, maxPixelSize: maxPixelSize) {
                loaded = ready
                return
            }
            loaded = nil
            do {
                let image: CGImage
                switch artwork {
                case .asset(let name):
                    image = try await ArtworkLoader.shared.image(forAsset: name, maxPixelSize: maxPixelSize)
                case .url(let url):
                    image = try await ArtworkLoader.shared.image(for: url, maxPixelSize: maxPixelSize)
                case .none:
                    return
                }
                if case .url = artwork {
                    withAnimation(.easeOut(duration: 0.25)) { loaded = image }
                } else {
                    loaded = image
                }
            } catch is CancellationError {
                // View went away, nothing to show.
            } catch {
                failed = true
            }
        }
    }

    private var proceduralPlaceholder: some View {
        Rectangle()
            .fill(.black)
            .cardEffect(.nebula(palette: .violet, intensity: 0.9))
    }
}

/// Shimmering block used while artwork loads.
public struct LoadingPlaceholder: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Color(white: 0.22))
            .cardEffect(.shimmer(intensity: 0.45, angle: 25))
            .cardMotionIdle(minimumInterval: 1 / 30)
    }
}
