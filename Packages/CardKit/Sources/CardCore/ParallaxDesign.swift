import Foundation

/// A card whose picture is built from layers standing at different
/// depths: tilt it and they slide apart. Two looks: a neon window with a
/// scene behind its glass, or a rimmed poster with a glowing backdrop.
public struct ParallaxDesign: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var style: ParallaxStyle
    public var layers: [ParallaxLayer]
    public var frame: ParallaxFrame
    public var back: ParallaxBack
    public var motion: ParallaxMotion

    public init(id: String, name: String, style: ParallaxStyle, layers: [ParallaxLayer], frame: ParallaxFrame, back: ParallaxBack, motion: ParallaxMotion = ParallaxMotion()) {
        self.id = id
        self.name = name
        self.style = style
        self.layers = layers
        self.frame = frame
        self.back = back
        self.motion = motion
    }

    /// Width over height: parallax cards are 2:3.
    public static let aspectRatio: Double = 2.0 / 3.0
}

public enum ParallaxStyle: String, Hashable, Sendable, Codable {
    /// A glowing neon frame around a window with the scene behind it.
    case neon
    /// A thin rim line; the layers can stand out of the card.
    case rim
}

/// Colours and chrome of the card itself.
public struct ParallaxFrame: Hashable, Sendable, Codable {
    /// Edge colours, first to last along the frame.
    public var edge1: CardColor
    public var edge2: CardColor
    public var edge3: CardColor
    /// Strength of the frame glow (0…2).
    public var glow: Double
    /// Colour of the card plate.
    public var plate: CardColor
    /// Thin line around the window.
    public var line: CardColor
    /// Shade in the corners.
    public var shade: CardColor
    /// Corner radius as a fraction of the card width (the reference uses em on a 40-em card).
    public var cornerRadius: Double
    public var specks: ParallaxSpecks

    public init(edge1: CardColor, edge2: CardColor, edge3: CardColor, glow: Double = 1, plate: CardColor, line: CardColor, shade: CardColor, cornerRadius: Double = 1.9 / 40, specks: ParallaxSpecks = ParallaxSpecks()) {
        self.edge1 = edge1
        self.edge2 = edge2
        self.edge3 = edge3
        self.glow = glow
        self.plate = plate
        self.line = line
        self.shade = shade
        self.cornerRadius = cornerRadius
        self.specks = specks
    }
}

/// Floating specks over the scene.
public struct ParallaxSpecks: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case none, stardust, twinkle, glitter
    }
    public var kind: Kind
    public var colors: [CardColor]
    /// How many (0.2…2.5), how big (0.4…2.5), how fast (0.2…3).
    public var count: Double
    public var size: Double
    public var speed: Double

    public init(kind: Kind = .none, colors: [CardColor] = [CardColor(hex: 0xF4ECFF), CardColor(hex: 0xE2C4FF), CardColor(hex: 0xFFE6B0)], count: Double = 1, size: Double = 1, speed: Double = 1) {
        self.kind = kind
        self.colors = colors
        self.count = count
        self.size = size
        self.speed = speed
    }
}

/// The back of the card.
public struct ParallaxBack: Hashable, Sendable, Codable {
    public var title: String
    public var subtitle: String
    /// Id of an image layer shown small in the middle, nil for the badge.
    public var pictureLayer: String?
    public var background: CardColor
    public var edge: CardColor
    public var accent: CardColor
    public var titleColor: CardColor
    public var subtitleColor: CardColor

    public init(title: String, subtitle: String, pictureLayer: String? = nil, background: CardColor, edge: CardColor, accent: CardColor, titleColor: CardColor, subtitleColor: CardColor) {
        self.title = title
        self.subtitle = subtitle
        self.pictureLayer = pictureLayer
        self.background = background
        self.edge = edge
        self.accent = accent
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
    }
}

/// How the card moves under the finger.
public struct ParallaxMotion: Hashable, Sendable, Codable {
    /// Degrees of tilt at full pointer travel.
    public var tilt: Double
    /// How far the layers travel with the depth (0…3).
    public var parallax: Double
    /// Spring response (0.3…2).
    public var response: Double
    /// Gentle sway when nothing touches the card.
    public var sways: Bool
    /// Strength of the glare over the window (0…1).
    public var glare: Double
    public var glareColor: CardColor

    public init(tilt: Double = 22, parallax: Double = 1.3, response: Double = 1, sways: Bool = true, glare: Double = 0.5, glareColor: CardColor = CardColor(hex: 0xFFFFFF)) {
        self.tilt = tilt
        self.parallax = parallax
        self.response = response
        self.sways = sways
        self.glare = glare
        self.glareColor = glareColor
    }
}

/// One layer of the scene.
public struct ParallaxLayer: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    /// Distance behind the glass (positive) or in front of it (negative), −8…14.
    public var depth: Double
    public var opacity: Double
    /// Centre, as a fraction of the window (0…1; cover layers ignore it).
    public var x: Double
    public var y: Double
    /// Width as a fraction of the window width.
    public var width: Double
    /// Stands out of the window instead of being clipped by it.
    public var pops: Bool
    public var content: ParallaxContent

    public init(id: String, name: String, depth: Double, opacity: Double = 1, x: Double = 0.5, y: Double = 0.5, width: Double = 1, pops: Bool = false, content: ParallaxContent) {
        self.id = id
        self.name = name
        self.depth = depth
        self.opacity = opacity
        self.x = x
        self.y = y
        self.width = width
        self.pops = pops
        self.content = content
    }

    /// Fills the window edge to edge (a cover picture or a backdrop).
    public var fillsWindow: Bool {
        switch content {
        case .glow: true
        case .image(let image): image.covers
        default: false
        }
    }
}

public enum ParallaxContent: Hashable, Sendable, Codable {
    case image(ParallaxImage)
    case glow(ParallaxGlow)
    case word(ParallaxWord)
    case title(ParallaxTitle)
    case box(ParallaxBox)
    case specs(ParallaxSpecs)
}

/// A picture, full-bleed or free-standing with its own light and shadow.
public struct ParallaxImage: Hashable, Sendable, Codable {
    public var artwork: CardArtwork
    /// Width over height of the picture, so a free-standing one gets its natural height.
    public var aspect: Double
    /// Fill the window.
    public var covers: Bool
    /// Cut the picture out on its dark background (for pictures without transparency).
    public var keyedOnBlack: Bool
    public var glow: Bool
    public var glowColor: CardColor
    /// Size of the glow relative to the picture (0.2…3.5).
    public var glowSize: Double
    public var shadow: Bool
    public var shadowColor: CardColor
    public var reflects: Bool
    /// A light that slides across the picture as the card tilts.
    public var sheen: Bool
    public var sheenColor: CardColor
    /// A slow breathing scale.
    public var breathes: Bool

    public init(artwork: CardArtwork, aspect: Double = 1, covers: Bool = false, keyedOnBlack: Bool = false, glow: Bool = false, glowColor: CardColor = CardColor(hex: 0xC8AAFF), glowSize: Double = 1, shadow: Bool = false, shadowColor: CardColor = CardColor(hex: 0x000000), reflects: Bool = false, sheen: Bool = false, sheenColor: CardColor = CardColor(hex: 0xFFFFFF), breathes: Bool = false) {
        self.artwork = artwork
        self.aspect = aspect
        self.covers = covers
        self.keyedOnBlack = keyedOnBlack
        self.glow = glow
        self.glowColor = glowColor
        self.glowSize = glowSize
        self.shadow = shadow
        self.shadowColor = shadowColor
        self.reflects = reflects
        self.sheen = sheen
        self.sheenColor = sheenColor
        self.breathes = breathes
    }
}

/// A glowing backdrop: a tone, rays from the top, rings and a floor.
public struct ParallaxGlow: Hashable, Sendable, Codable {
    public var light: CardColor
    public var middle: CardColor
    public var edge: CardColor
    public var rays: Bool
    public var raysColor: CardColor
    public var rings: Bool
    public var ringColor: CardColor
    public var floor: Bool
    public var floorColor: CardColor
    public var lineColor: CardColor
    public var spotColor: CardColor

    public init(light: CardColor, middle: CardColor, edge: CardColor, rays: Bool = true, raysColor: CardColor, rings: Bool = true, ringColor: CardColor, floor: Bool = true, floorColor: CardColor, lineColor: CardColor, spotColor: CardColor) {
        self.light = light
        self.middle = middle
        self.edge = edge
        self.rays = rays
        self.raysColor = raysColor
        self.rings = rings
        self.ringColor = ringColor
        self.floor = floor
        self.floorColor = floorColor
        self.lineColor = lineColor
        self.spotColor = spotColor
    }
}

/// A giant word behind the subject.
public struct ParallaxWord: Hashable, Sendable, Codable {
    public var text: String
    public var top: CardColor
    public var bottom: CardColor
    public var stroke: CardColor
    /// Vertical stretch of the letters (0.6…2.4).
    public var stretch: Double

    public init(text: String, top: CardColor, bottom: CardColor, stroke: CardColor, stretch: Double = 1.55) {
        self.text = text
        self.top = top
        self.bottom = bottom
        self.stroke = stroke
        self.stretch = stretch
    }
}

/// Small line, big name, optional badge.
public struct ParallaxTitle: Hashable, Sendable, Codable {
    public var brand: String
    public var model: String
    public var brandColor: CardColor
    public var modelColor: CardColor
    public var glowColor: CardColor
    public var badge: Bool
    public var badgeColor: CardColor

    public init(brand: String, model: String, brandColor: CardColor, modelColor: CardColor, glowColor: CardColor, badge: Bool = true, badgeColor: CardColor) {
        self.brand = brand
        self.model = model
        self.brandColor = brandColor
        self.modelColor = modelColor
        self.glowColor = glowColor
        self.badge = badge
        self.badgeColor = badgeColor
    }
}

/// A bordered text box.
public struct ParallaxBox: Hashable, Sendable, Codable {
    public var heading: String
    public var body: String
    public var headingColor: CardColor
    public var textColor: CardColor
    public var borderColor: CardColor
    public var fillColor: CardColor

    public init(heading: String, body: String, headingColor: CardColor, textColor: CardColor, borderColor: CardColor, fillColor: CardColor) {
        self.heading = heading
        self.body = body
        self.headingColor = headingColor
        self.textColor = textColor
        self.borderColor = borderColor
        self.fillColor = fillColor
    }
}

/// Up to four figures with an icon each.
public struct ParallaxSpecs: Hashable, Sendable, Codable {
    public struct Spec: Hashable, Sendable, Codable {
        public var value: String
        public var unit: String
        public var label: String
        /// SF Symbol name, empty for none.
        public var symbol: String

        public init(value: String, unit: String = "", label: String, symbol: String = "") {
            self.value = value
            self.unit = unit
            self.label = label
            self.symbol = symbol
        }
    }
    public var items: [Spec]
    public var textColor: CardColor
    public var iconColor: CardColor
    public var lineColor: CardColor

    public init(items: [Spec], textColor: CardColor, iconColor: CardColor, lineColor: CardColor) {
        self.items = items
        self.textColor = textColor
        self.iconColor = iconColor
        self.lineColor = lineColor
    }
}

public extension CardColor {
    /// Linear blend toward another colour.
    func mixed(with other: CardColor, _ t: Double) -> CardColor {
        let k = min(1, max(0, t))
        return CardColor(red: red + (other.red - red) * k, green: green + (other.green - green) * k, blue: blue + (other.blue - blue) * k)
    }

    static let black = CardColor(hex: 0x000000)
    static let white = CardColor(hex: 0xFFFFFF)
}
