import CardCore
import CardFX
import SwiftUI

/// Everything that makes a booster look like itself. The wrapper follows the
/// modern pocket-pack layout: a top band (brand, set code, bright seam), a
/// full-bleed cover, and a bottom band of another colour carrying the set
/// name on a plate. Swap a design to re-skin the pack.
public struct PackDesign: Hashable, Sendable {
    /// Set name printed big over the bottom of the cover ("GENETIC APEX").
    public var title: String
    /// Pack name printed on the plate under the title ("Charizard").
    public var subtitle: String?
    /// Small brand line in the top band.
    public var brand: String
    /// Short set code shown in the top-right badge ("A1").
    public var setCode: String?
    /// Full-bleed picture of the wrapper.
    public var cover: CardArtwork
    /// Colour of the top band (the strip that gets torn).
    public var topColor: CardColor
    /// Colour of the bottom band.
    public var bottomColor: CardColor
    /// Colour of the name plate and of the seam glow.
    public var accent: CardColor
    /// Hue (0…1) of the metallic sheen over the cover.
    public var foilHue: Double
    /// SF Symbol used as brand emblem.
    public var emblemSymbol: String
    /// Number of cards announced on the wrapper.
    public var cardCount: Int
    /// Height of the top band (= tear strip) as a fraction of the pack height.
    public var stripFraction: CGFloat
    /// Height of the bottom band as a fraction of the pack height.
    public var bottomFraction: CGFloat

    public init(
        title: String,
        subtitle: String? = nil,
        brand: String = "AMAZING CARDS",
        setCode: String? = nil,
        cover: CardArtwork,
        topColor: CardColor,
        bottomColor: CardColor,
        accent: CardColor = .gold,
        foilHue: Double = 0.62,
        emblemSymbol: String = "sparkles",
        cardCount: Int = 5,
        stripFraction: CGFloat = 0.14,
        bottomFraction: CGFloat = 0.13
    ) {
        self.title = title
        self.subtitle = subtitle
        self.brand = brand
        self.setCode = setCode
        self.cover = cover
        self.topColor = topColor
        self.bottomColor = bottomColor
        self.accent = accent
        self.foilHue = foilHue
        self.emblemSymbol = emblemSymbol
        self.cardCount = cardCount
        self.stripFraction = stripFraction
        self.bottomFraction = bottomFraction
    }

    /// Packs share the card ratio so the cards stay hidden behind them until opened.
    public static let aspectRatio: CGFloat = 63.0 / 88.0
}
