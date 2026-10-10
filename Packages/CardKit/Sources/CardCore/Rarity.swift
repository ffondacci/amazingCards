import Foundation

/// Rarity tier. Ordered so that `max()` picks the best pull of a pack.
public enum Rarity: Int, CaseIterable, Comparable, Hashable, Sendable, Codable {
    case common = 0
    case uncommon
    case rare
    case epic
    case legendary

    public static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        case .epic: "Epic"
        case .legendary: "Legendary"
        }
    }

    /// SF Symbol printed next to the card number.
    public var symbolName: String {
        switch self {
        case .common: "circle.fill"
        case .uncommon: "diamond.fill"
        case .rare: "star.fill"
        case .epic: "sparkles"
        case .legendary: "crown.fill"
        }
    }

    public var color: CardColor {
        switch self {
        case .common: CardColor(hex: 0x9AA0A6)
        case .uncommon: CardColor(hex: 0x4CC2A8)
        case .rare: CardColor(hex: 0x4D8DF0)
        case .epic: CardColor(hex: 0xB45CFF)
        case .legendary: CardColor(hex: 0xF2B632)
        }
    }

    /// Relative pull weight used by `BoosterGenerator` for its "wild" slot.
    public var pullWeight: Double {
        switch self {
        case .common: 50
        case .uncommon: 28
        case .rare: 14
        case .epic: 6
        case .legendary: 2
        }
    }

    /// A sensible finish for freshly generated cards of this rarity.
    public var defaultFinish: CardFinish {
        switch self {
        case .common, .uncommon: .matte
        case .rare: .holo
        case .epic: .rainbow
        case .legendary: .gold
        }
    }
}
