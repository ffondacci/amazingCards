import CardUI
import SwiftUI

/// Sizes of the pack flow, as fractions of the available space. Set one
/// for the whole app with `.packLayout(_:)`; views read it from the
/// environment. Every value is a fraction so the same layout fits an
/// iPhone, an iPad or a split-view window.
public struct PackLayout: Hashable, Sendable {
    /// Width the cards may use in the opening, as a fraction of the available width.
    public var cardWidthFraction: CGFloat
    /// Height the sealed pack may use in the opening, as a fraction of the
    /// available height. The pack is taller than a card, so this is what
    /// bounds the card size on most phones.
    public var cardHeightFraction: CGFloat
    /// Width of the sealed pack relative to the card width (a hair larger
    /// keeps the deck hidden until the pack opens).
    public var packScale: CGFloat
    /// Width of a pack in the carousel, as a fraction of the available width.
    public var carouselPackWidthFraction: CGFloat
    /// Height a carousel pack may use, as a fraction of the available height.
    public var carouselPackHeightFraction: CGFloat
    /// Upper bound of the card width in points (nil = none), for very wide hosts.
    public var maxCardWidth: CGFloat?

    public init(
        cardWidthFraction: CGFloat = 0.8,
        cardHeightFraction: CGFloat = 0.74,
        packScale: CGFloat = 1.05,
        carouselPackWidthFraction: CGFloat = 0.58,
        carouselPackHeightFraction: CGFloat = 0.68,
        maxCardWidth: CGFloat? = 520
    ) {
        self.cardWidthFraction = cardWidthFraction
        self.cardHeightFraction = cardHeightFraction
        self.packScale = packScale
        self.carouselPackWidthFraction = carouselPackWidthFraction
        self.carouselPackHeightFraction = carouselPackHeightFraction
        self.maxCardWidth = maxCardWidth
    }

    /// Default: big cards, pack a little larger than the cards.
    public static let standard = PackLayout()
    /// Smaller cards and packs, for dense screens or small hosts.
    public static let compact = PackLayout(
        cardWidthFraction: 0.64, cardHeightFraction: 0.56,
        carouselPackWidthFraction: 0.46, carouselPackHeightFraction: 0.56
    )
    /// Cards and packs as large as the screen allows.
    public static let large = PackLayout(
        cardWidthFraction: 0.9, cardHeightFraction: 0.76,
        carouselPackWidthFraction: 0.68, carouselPackHeightFraction: 0.76, maxCardWidth: nil
    )

    /// Card width for an available size: always a hair narrower than the
    /// sealed pack, so the deck stays hidden until the pack opens.
    public func cardWidth(in size: CGSize) -> CGFloat {
        packSize(in: size).width / packScale
    }

    /// Pack size for an available size: as wide as the cards allow, no
    /// taller than `cardHeightFraction` of the height.
    public func packSize(in size: CGSize) -> CGSize {
        var width = min(size.width * cardWidthFraction * packScale, size.height * cardHeightFraction * PackDesign.aspectRatio)
        if let maxCardWidth { width = min(width, maxCardWidth * packScale) }
        width = max(width, 1)
        return CGSize(width: width, height: width / PackDesign.aspectRatio)
    }

    /// Width of a pack in the carousel for an available size.
    public func carouselPackWidth(in size: CGSize) -> CGFloat {
        var width = min(size.width * carouselPackWidthFraction, size.height * carouselPackHeightFraction * PackDesign.aspectRatio)
        if let maxCardWidth { width = min(width, maxCardWidth * packScale) }
        return max(width, 1)
    }
}

private struct PackLayoutKey: EnvironmentKey {
    static let defaultValue = PackLayout.standard
}

public extension EnvironmentValues {
    /// Sizes of the pack flow (carousel and opening).
    var packLayout: PackLayout {
        get { self[PackLayoutKey.self] }
        set { self[PackLayoutKey.self] = newValue }
    }
}

public extension View {
    /// Sets the sizes of every pack carousel and opening in the hierarchy.
    func packLayout(_ layout: PackLayout) -> some View {
        environment(\.packLayout, layout)
    }
}
