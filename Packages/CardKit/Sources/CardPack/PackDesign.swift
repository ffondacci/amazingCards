import CardCore
import CardFX
import SwiftUI

/// Everything that makes a booster look like itself: colours, foil tint,
/// cover artwork, title and emblem. Swap it to re-skin the pack.
public struct PackDesign: Hashable, Sendable {
    public var title: String
    public var subtitle: String?
    /// Picture shown in the window of the wrapper.
    public var cover: CardArtwork
    /// Vertical gradient of the wrapper.
    public var baseColors: [CardColor]
    /// Hue (0…1) of the metallic foil highlights.
    public var foilHue: Double
    /// SF Symbol printed under the window.
    public var emblemSymbol: String
    /// Colour of the crimped bands and the tear strip.
    public var bandColor: CardColor
    /// Number of cards announced on the wrapper.
    public var cardCount: Int
    /// Height of the tear strip as a fraction of the pack height.
    public var stripFraction: CGFloat

    public init(
        title: String,
        subtitle: String? = nil,
        cover: CardArtwork,
        baseColors: [CardColor],
        foilHue: Double = 0.62,
        emblemSymbol: String = "sparkles",
        bandColor: CardColor = .ink,
        cardCount: Int = 5,
        stripFraction: CGFloat = 0.17
    ) {
        self.title = title
        self.subtitle = subtitle
        self.cover = cover
        self.baseColors = baseColors
        self.foilHue = foilHue
        self.emblemSymbol = emblemSymbol
        self.bandColor = bandColor
        self.cardCount = cardCount
        self.stripFraction = stripFraction
    }

    /// Packs share the card ratio so the cards stay hidden behind them until opened.
    public static let aspectRatio: CGFloat = 63.0 / 88.0
}
