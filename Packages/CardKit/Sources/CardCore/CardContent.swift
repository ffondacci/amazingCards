import Foundation

/// Which visual template renders a card. Templates differ in framing: a
/// painting is borderless (the artwork bleeds to the edges), an artist or a
/// creature sits inside a frame, a celestial object floats on a star field.
public enum CardTemplate: String, CaseIterable, Hashable, Sendable, Codable {
    case creature
    case artist
    case painting
    case celestial

    /// Framed templates keep a coloured border and an inset artwork window.
    public var hasBorder: Bool {
        switch self {
        case .creature, .artist: true
        case .painting, .celestial: false
        }
    }

    public var displayName: String {
        switch self {
        case .creature: "Creature"
        case .artist: "Artist"
        case .painting: "Painting"
        case .celestial: "Celestial object"
        }
    }
}

/// The subject of a card. Each case carries the data its template needs.
public enum CardContent: Hashable, Sendable, Codable {
    case creature(Creature)
    case artist(Artist)
    case painting(Painting)
    case celestial(CelestialObject)

    public var template: CardTemplate {
        switch self {
        case .creature: .creature
        case .artist: .artist
        case .painting: .painting
        case .celestial: .celestial
        }
    }
}

// MARK: - Creature (trading-card style)

/// Elemental type of a creature, drives the frame colour and the energy icons.
public enum CreatureElement: String, CaseIterable, Hashable, Sendable, Codable {
    case fire, water, grass, electric, psychic, rock, metal, cosmic, art, colorless

    public var displayName: String { rawValue.capitalized }

    public var color: CardColor {
        switch self {
        case .fire: CardColor(hex: 0xE8542F)
        case .water: CardColor(hex: 0x3D8FE0)
        case .grass: CardColor(hex: 0x5BB543)
        case .electric: CardColor(hex: 0xF2C530)
        case .psychic: CardColor(hex: 0x9B59B6)
        case .rock: CardColor(hex: 0xA3783E)
        case .metal: CardColor(hex: 0x9AA7B2)
        case .cosmic: CardColor(hex: 0x4B3FBF)
        case .art: CardColor(hex: 0xD9534F)
        case .colorless: CardColor(hex: 0xD6D6D6)
        }
    }

    /// SF Symbol used as energy icon.
    public var symbolName: String {
        switch self {
        case .fire: "flame.fill"
        case .water: "drop.fill"
        case .grass: "leaf.fill"
        case .electric: "bolt.fill"
        case .psychic: "eye.fill"
        case .rock: "mountain.2.fill"
        case .metal: "gearshape.fill"
        case .cosmic: "sparkles"
        case .art: "paintbrush.pointed.fill"
        case .colorless: "star.fill"
        }
    }
}

/// One attack line: energy cost, name, damage and rule text.
public struct Attack: Hashable, Sendable, Codable {
    public var name: String
    public var cost: [CreatureElement]
    public var damage: Int?
    public var text: String?

    public init(name: String, cost: [CreatureElement], damage: Int? = nil, text: String? = nil) {
        self.name = name
        self.cost = cost
        self.damage = damage
        self.text = text
    }
}

/// Data of a creature card (the classic framed trading-card layout).
public struct Creature: Hashable, Sendable, Codable {
    public var stage: String
    public var hitPoints: Int
    public var element: CreatureElement
    /// Line printed under the artwork, e.g. "No. 235  Painter  HT: 3'11"".
    public var species: String
    public var attacks: [Attack]
    public var weakness: CreatureElement?
    public var resistance: CreatureElement?
    public var retreatCost: Int
    public var flavorText: String?

    public init(
        stage: String = "Basic",
        hitPoints: Int,
        element: CreatureElement,
        species: String,
        attacks: [Attack],
        weakness: CreatureElement? = nil,
        resistance: CreatureElement? = nil,
        retreatCost: Int = 1,
        flavorText: String? = nil
    ) {
        self.stage = stage
        self.hitPoints = hitPoints
        self.element = element
        self.species = species
        self.attacks = attacks
        self.weakness = weakness
        self.resistance = resistance
        self.retreatCost = retreatCost
        self.flavorText = flavorText
    }
}

// MARK: - Art collection

/// Data of an artist card (framed portrait, biography strip).
public struct Artist: Hashable, Sendable, Codable {
    public var born: String
    public var died: String?
    public var nationality: String
    public var movement: String
    public var biography: String
    public var notableWorks: [String]
    public var quote: String?

    public init(
        born: String,
        died: String? = nil,
        nationality: String,
        movement: String,
        biography: String,
        notableWorks: [String] = [],
        quote: String? = nil
    ) {
        self.born = born
        self.died = died
        self.nationality = nationality
        self.movement = movement
        self.biography = biography
        self.notableWorks = notableWorks
        self.quote = quote
    }

    /// "1853 – 1890" or "1853 –" when alive.
    public var lifespan: String {
        if let died { return "\(born) – \(died)" }
        return "\(born) –"
    }
}

/// Data of a painting card (borderless, full-bleed artwork, caption strip).
public struct Painting: Hashable, Sendable, Codable {
    public var artist: String
    public var year: String
    public var medium: String
    public var dimensions: String?
    public var location: String?
    public var description: String

    public init(
        artist: String,
        year: String,
        medium: String,
        dimensions: String? = nil,
        location: String? = nil,
        description: String
    ) {
        self.artist = artist
        self.year = year
        self.medium = medium
        self.dimensions = dimensions
        self.location = location
        self.description = description
    }
}

// MARK: - Celestial collection

public enum CelestialKind: String, CaseIterable, Hashable, Sendable, Codable {
    case galaxy, nebula, planet, star, cluster, moon, comet

    public var displayName: String { rawValue.capitalized }

    public var symbolName: String {
        switch self {
        case .galaxy: "hurricane"
        case .nebula: "cloud.fill"
        case .planet: "globe.americas.fill"
        case .star: "star.fill"
        case .cluster: "circle.hexagongrid.fill"
        case .moon: "moon.fill"
        case .comet: "sparkle"
        }
    }

    public var color: CardColor {
        switch self {
        case .galaxy: CardColor(hex: 0x8E7CFF)
        case .nebula: CardColor(hex: 0xFF6FB5)
        case .planet: CardColor(hex: 0xF0B35B)
        case .star: CardColor(hex: 0xFFE28A)
        case .cluster: CardColor(hex: 0x7FD4FF)
        case .moon: CardColor(hex: 0xC8CDD6)
        case .comet: CardColor(hex: 0x9EF5E3)
        }
    }
}

/// Data of a celestial-object card (dark borderless layout with data strip).
public struct CelestialObject: Hashable, Sendable, Codable {
    /// Catalogue designations, e.g. "M31 · NGC 224".
    public var designation: String
    public var kind: CelestialKind
    public var constellation: String
    public var distance: String
    public var apparentMagnitude: Double?
    public var apparentSize: String?
    public var description: String

    public init(
        designation: String,
        kind: CelestialKind,
        constellation: String,
        distance: String,
        apparentMagnitude: Double? = nil,
        apparentSize: String? = nil,
        description: String
    ) {
        self.designation = designation
        self.kind = kind
        self.constellation = constellation
        self.distance = distance
        self.apparentMagnitude = apparentMagnitude
        self.apparentSize = apparentSize
        self.description = description
    }
}
