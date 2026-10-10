import Foundation

/// Foil families implemented by the `ck_holo` shader. Raw values are the
/// `style` argument of the shader, keep them in sync with `Holo.metal`.
public enum HoloStyle: Int, CaseIterable, Hashable, Sendable, Codable {
    case regular = 0
    case cosmos
    case reverseHolo
    case galaxy
    case rainbow
    case gold
    case amazing
    case radiant
    case prism
    case pearl
    case brushedMetal
    case fullArt
    case interference

    public var displayName: String {
        switch self {
        case .regular: "Regular holo"
        case .cosmos: "Cosmos"
        case .reverseHolo: "Reverse holo"
        case .galaxy: "Galaxy"
        case .rainbow: "Rainbow"
        case .gold: "Gold"
        case .amazing: "Amazing"
        case .radiant: "Radiant"
        case .prism: "Prism"
        case .pearl: "Pearl"
        case .brushedMetal: "Brushed metal"
        case .fullArt: "Full art"
        case .interference: "Interference"
        }
    }

    /// Short description for catalogs and documentation.
    public var summary: String {
        switch self {
        case .regular: "Rainbow bands, scan lines and moving bars."
        case .cosmos: "Three parallax star layers over a soft nebula."
        case .reverseHolo: "Textured silver foil meant for the frame."
        case .galaxy: "Slowly drifting coloured gas clouds and stars."
        case .rainbow: "Crossing rainbow gradients with glitter."
        case .gold: "Geometric gold foil and sparkles."
        case .amazing: "Saturated paint splashes with glitter."
        case .radiant: "Etched diagonal lattice with sparkles."
        case .prism: "Diffraction rings around the finger, CD like."
        case .pearl: "Thin-film iridescence driven by luminance."
        case .brushedMetal: "Anisotropic streaks and a specular band."
        case .fullArt: "Vertical sun-pillar rainbow with etching."
        case .interference: "Wavy interference field with ridges."
        }
    }

    /// Styles whose look changes over time even when the card is still.
    public var isTimeDriven: Bool {
        switch self {
        case .regular, .reverseHolo, .prism, .pearl, .brushedMetal, .fullArt, .interference: false
        case .cosmos, .galaxy, .rainbow, .gold, .amazing, .radiant: true
        }
    }
}

/// Colour schemes of the `ck_nebula` generator.
public enum NebulaPalette: Int, CaseIterable, Hashable, Sendable, Codable {
    case violet = 0
    case teal
    case ember
    case emerald

    public var displayName: String {
        switch self {
        case .violet: "Violet"
        case .teal: "Teal & gold"
        case .ember: "Ember"
        case .emerald: "Emerald"
        }
    }
}
