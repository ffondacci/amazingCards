import CardCore
import CardFX
import SwiftUI

/// Design of the back of a card.
public struct CardBackDesign: Hashable, Sendable {
    public var colors: [CardColor]
    public var nebulaPalette: NebulaPalette
    public var emblemSymbol: String
    public var title: String
    public var borderColor: CardColor

    public init(
        colors: [CardColor],
        nebulaPalette: NebulaPalette = .violet,
        emblemSymbol: String = "sparkles",
        title: String = "AMAZING CARDS",
        borderColor: CardColor = .gold
    ) {
        self.colors = colors
        self.nebulaPalette = nebulaPalette
        self.emblemSymbol = emblemSymbol
        self.title = title
        self.borderColor = borderColor
    }

    public static let midnight = CardBackDesign(
        colors: [CardColor(hex: 0x141A3A), CardColor(hex: 0x2B1E5C)],
        nebulaPalette: .violet
    )
    public static let gallery = CardBackDesign(
        colors: [CardColor(hex: 0x2A1A12), CardColor(hex: 0x5A3420)],
        nebulaPalette: .ember,
        emblemSymbol: "paintpalette.fill",
        title: "GALLERY",
        borderColor: CardColor(hex: 0xE2B86A)
    )
    public static let observatory = CardBackDesign(
        colors: [CardColor(hex: 0x03101C), CardColor(hex: 0x0B2A3A)],
        nebulaPalette: .teal,
        emblemSymbol: "moon.stars.fill",
        title: "OBSERVATORY",
        borderColor: .aurora
    )
}

/// Visual theme shared by every card template: frame colours, paper tint,
/// corner radius, typography and the back design. Inject with
/// `.cardTheme(_:)` to restyle a whole collection without touching templates.
public struct CardTheme: Hashable, Sendable {
    public var name: String
    /// Gradient of the creature frame.
    public var creatureFrame: [CardColor]
    /// Strength of the pastel holo paper behind framed cards (0…1).
    public var paperIntensity: Double
    /// Corner radius as a percentage of the card width.
    public var cornerRadiusPercent: Double
    /// Font design for titles, nil keeps each template's own choice.
    public var titleDesign: Font.Design?
    public var back: CardBackDesign

    public init(
        name: String,
        creatureFrame: [CardColor],
        paperIntensity: Double = 0.9,
        cornerRadiusPercent: Double = 4.5,
        titleDesign: Font.Design? = nil,
        back: CardBackDesign = .midnight
    ) {
        self.name = name
        self.creatureFrame = creatureFrame
        self.paperIntensity = paperIntensity
        self.cornerRadiusPercent = cornerRadiusPercent
        self.titleDesign = titleDesign
        self.back = back
    }

    /// Warm yellow frame, the classic print.
    public static let classic = CardTheme(
        name: "Classic",
        creatureFrame: [CardColor(hex: 0xF7DC7A), CardColor(hex: 0xE9C44B)]
    )
    /// Black frames, serif titles, museum feel.
    public static let noir = CardTheme(
        name: "Noir",
        creatureFrame: [CardColor(hex: 0x1C1C22), CardColor(hex: 0x3A3A44)],
        paperIntensity: 0.55,
        cornerRadiusPercent: 3.2,
        titleDesign: .serif,
        back: .gallery
    )
    /// Silver frames, rounded corners, cool paper.
    public static let silver = CardTheme(
        name: "Silver",
        creatureFrame: [CardColor(hex: 0xE4E9EF), CardColor(hex: 0xB9C3CE)],
        paperIntensity: 0.7,
        cornerRadiusPercent: 6,
        titleDesign: .rounded,
        back: .observatory
    )

    public static let presets: [CardTheme] = [.classic, .noir, .silver]
}

private struct CardThemeKey: EnvironmentKey {
    static let defaultValue = CardTheme.classic
}

public extension EnvironmentValues {
    var cardTheme: CardTheme {
        get { self[CardThemeKey.self] }
        set { self[CardThemeKey.self] = newValue }
    }
}

public extension View {
    /// Applies a card theme to every card in the hierarchy.
    func cardTheme(_ theme: CardTheme) -> some View {
        environment(\.cardTheme, theme)
    }
}
