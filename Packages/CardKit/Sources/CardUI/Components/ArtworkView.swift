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
    }

    public var body: some View {
        switch artwork {
        case .asset(let name):
            Image(name, bundle: .main)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        case .url(let url):
            remote(url)
        case .none:
            proceduralPlaceholder
        }
    }

    @ViewBuilder
    private func remote(_ url: URL) -> some View {
        ZStack {
            if let loaded {
                Image(decorative: loaded, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if failed {
                proceduralPlaceholder
                    .overlay {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.7))
                    }
            } else {
                LoadingPlaceholder()
            }
        }
        .task(id: url) {
            loaded = nil
            failed = false
            do {
                let image = try await ArtworkLoader.shared.image(for: url, maxPixelSize: maxPixelSize)
                withAnimation(.easeOut(duration: 0.25)) { loaded = image }
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
            .cardMotionIdle()
            .cardEffect(.shimmer(intensity: 0.45, angle: 25))
    }
}
