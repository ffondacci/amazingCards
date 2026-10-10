import Foundation

/// Stable identifier of a card inside a collection. A plain string so that it
/// survives JSON round-trips and can be authored by hand in sample data.
public struct CardID: Hashable, Sendable, Codable, RawRepresentable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }
}

/// A collectible card: what it shows (`content` + `artwork`) and how it is
/// printed (`rarity` + `finish`). Pure data, safe to send between actors.
public struct Card: Identifiable, Hashable, Sendable, Codable {
    public var id: CardID
    /// Main title (creature name, artist name, painting title, object name).
    public var title: String
    /// Secondary line shown under or next to the title.
    public var subtitle: String?
    public var artwork: CardArtwork
    public var content: CardContent
    public var rarity: Rarity
    public var finish: CardFinish
    /// Position inside its set, e.g. 12/151.
    public var number: CardNumber?
    public var setName: String?
    /// Illustrator / photo credit printed in the footer.
    public var credit: String?
    /// Optional explicit accent colour. When nil, the template derives one from the content.
    public var accent: CardColor?

    public init(
        id: CardID,
        title: String,
        subtitle: String? = nil,
        artwork: CardArtwork,
        content: CardContent,
        rarity: Rarity = .common,
        finish: CardFinish = .matte,
        number: CardNumber? = nil,
        setName: String? = nil,
        credit: String? = nil,
        accent: CardColor? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.content = content
        self.rarity = rarity
        self.finish = finish
        self.number = number
        self.setName = setName
        self.credit = credit
        self.accent = accent
    }

    /// The visual template implied by the content.
    public var template: CardTemplate { content.template }

    /// True when the card carries a foil treatment (anything but `.matte`).
    public var isFoil: Bool { finish.isFoil }

    /// Returns a copy with another finish, handy to build demo variants.
    public func with(finish: CardFinish) -> Card {
        var copy = self
        copy.finish = finish
        return copy
    }

    /// Returns a copy with another rarity.
    public func with(rarity: Rarity) -> Card {
        var copy = self
        copy.rarity = rarity
        return copy
    }
}

/// Position of a card inside its set.
public struct CardNumber: Hashable, Sendable, Codable {
    public var index: Int
    public var total: Int

    public init(_ index: Int, of total: Int) {
        self.index = index
        self.total = total
    }

    /// "012/151" style, zero padded to the width of the total.
    public var formatted: String {
        let width = String(total).count
        let padded = String(repeating: "0", count: max(0, width - String(index).count)) + String(index)
        return "\(padded)/\(total)"
    }
}

/// Where the picture of a card comes from. Resolution happens in `CardUI`.
public enum CardArtwork: Hashable, Sendable, Codable {
    /// An image in the app's asset catalog (main bundle).
    case asset(String)
    /// A remote or file URL, loaded and downsampled asynchronously.
    case url(URL)
    /// No picture: the template draws a procedural background instead.
    case none
}

/// A colour in sRGB, kept framework-free so that `CardCore` stays pure.
public struct CardColor: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Hex literal such as `0xF5C518`.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Relative luminance (Rec. 601), used to pick readable text colours.
    public var luminance: Double { 0.299 * red + 0.587 * green + 0.114 * blue }

    public static let gold = CardColor(hex: 0xE8B923)
    public static let silver = CardColor(hex: 0xC9D1DA)
    public static let ink = CardColor(hex: 0x14161C)
    public static let paper = CardColor(hex: 0xF4EFE6)
    public static let cobalt = CardColor(hex: 0x2B4C9B)
    public static let vermilion = CardColor(hex: 0xE34234)
    public static let nebula = CardColor(hex: 0x7B4DFF)
    public static let aurora = CardColor(hex: 0x3BE0C8)
}

/// A named group of cards (a "set" or "expansion").
public struct CardSet: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var cards: [Card]

    public init(id: String, name: String, cards: [Card]) {
        self.id = id
        self.name = name
        self.cards = cards
    }

    public subscript(id cardID: CardID) -> Card? {
        cards.first { $0.id == cardID }
    }
}
