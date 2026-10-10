import CardCore
import CardFX

/// Which shader passes a finish applies, split by region of a framed card.
/// Borderless templates fold everything into `fullCard`.
public struct FinishRecipe: Hashable, Sendable {
    public var artwork: [CardEffect]
    public var frame: [CardEffect]
    public var fullCard: [CardEffect]

    public init(artwork: [CardEffect] = [], frame: [CardEffect] = [], fullCard: [CardEffect] = []) {
        self.artwork = artwork
        self.frame = frame
        self.fullCard = fullCard
    }

    public static let none = FinishRecipe()

    /// True when any pass animates over time (drives the motion clock).
    public var isTimeDriven: Bool {
        (artwork + frame + fullCard).contains { $0.isTimeDriven }
    }

    /// Builds the recipe of a finish for a template.
    public static func recipe(for finish: CardFinish, template: CardTemplate) -> FinishRecipe {
        let glare = CardEffect.glare(intensity: 0.3, radius: 0.95)
        guard let style = finish.holoStyle else {
            // Matte: only a soft glare so the card still feels physical.
            return FinishRecipe(fullCard: [.glare(intensity: 0.35, radius: 1.0)])
        }
        let foil = CardEffect.holo(style)
        let region = template.hasBorder ? finish.region : .fullCard
        switch region {
        case .artwork:
            return FinishRecipe(artwork: [foil, glare], fullCard: [.glare(intensity: 0.2, radius: 1.1)])
        case .frame:
            return FinishRecipe(artwork: [glare], frame: [foil], fullCard: [.glare(intensity: 0.2, radius: 1.1)])
        case .fullCard:
            return FinishRecipe(fullCard: [foil, glare])
        }
    }
}

public extension CardFinish {
    /// Shader style backing this finish, nil for matte.
    var holoStyle: HoloStyle? {
        switch self {
        case .matte: nil
        case .holo: .regular
        case .reverseHolo: .reverseHolo
        case .cosmos: .cosmos
        case .galaxy: .galaxy
        case .rainbow: .rainbow
        case .gold: .gold
        case .amazing: .amazing
        case .radiant: .radiant
        case .prism: .prism
        case .pearl: .pearl
        case .brushedMetal: .brushedMetal
        case .fullArt: .fullArt
        case .interference: .interference
        }
    }
}
