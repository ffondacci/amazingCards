import CardCore
import CardFX
import SwiftUI

/// Draws a card at any size. The parent decides the size, the card keeps its
/// 63 × 88 ratio and scales every detail with `CardMetrics`.
///
/// Finish effects read the environment `cardMotion`; wrap the card in a
/// `CardMotionStage` (or use `InteractiveCardView`) to make them react.
public struct CardView: View {
    public var card: Card
    /// Set to false for lists and thumbnails where the foil would be wasted.
    public var showsFinish: Bool
    @Environment(\.cardTheme) private var theme

    public init(card: Card, showsFinish: Bool = true) {
        self.card = card
        self.showsFinish = showsFinish
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = CardMetrics(size: proxy.size, cornerRadiusPercent: theme.cornerRadiusPercent)
            CardFaceView(card: card, metrics: metrics, showsFinish: showsFinish)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(metrics.shape)
                .overlay {
                    metrics.shape.strokeBorder(.white.opacity(0.18), lineWidth: max(metrics.pt(0.35), 0.5))
                }
        }
        .aspectRatio(CardMetrics.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.title), \(card.rarity.displayName), \(card.finish.displayName)")
    }
}

/// Picks the template for the content and applies the finish recipe on the
/// regions the template exposes.
struct CardFaceView: View {
    let card: Card
    let metrics: CardMetrics
    let showsFinish: Bool

    private var recipe: FinishRecipe {
        showsFinish ? FinishRecipe.recipe(for: card.finish, template: card.template) : .none
    }

    var body: some View {
        let recipe = recipe
        Group {
            switch card.content {
            case .creature(let creature):
                CreatureCardFace(card: card, creature: creature, metrics: metrics, recipe: recipe)
            case .artist(let artist):
                ArtistCardFace(card: card, artist: artist, metrics: metrics, recipe: recipe)
            case .painting(let painting):
                PaintingCardFace(card: card, painting: painting, metrics: metrics, recipe: recipe)
            case .celestial(let object):
                CelestialCardFace(card: card, object: object, metrics: metrics, recipe: recipe)
            }
        }
        .cardEffects(recipe.fullCard)
    }
}

/// Convenience: an interactive card with tilt, gyroscope and shadow.
public struct InteractiveCardView: View {
    public var card: Card
    public var interaction: CardMotionInteraction
    public var usesDeviceMotion: Bool
    public var showcase: Bool

    public init(card: Card, interaction: CardMotionInteraction = .drag, usesDeviceMotion: Bool = true, showcase: Bool = false) {
        self.card = card
        self.interaction = interaction
        self.usesDeviceMotion = usesDeviceMotion
        self.showcase = showcase
    }

    public var body: some View {
        let animates = FinishRecipe.recipe(for: card.finish, template: card.template).isTimeDriven
        CardMotionStage(
            interaction: interaction,
            usesDeviceMotion: usesDeviceMotion,
            animates: animates,
            showcase: showcase
        ) {
            CardView(card: card)
        }
    }
}
