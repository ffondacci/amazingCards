import Foundation

/// Printing treatment of a card. `CardUI` maps each finish to a recipe of
/// shader effects and to the region they cover (artwork window, frame, or
/// the whole card).
public enum CardFinish: String, CaseIterable, Hashable, Sendable, Codable {
    /// Plain print, only a soft glare follows the finger.
    case matte
    /// Rainbow bands and scan lines inside the artwork window.
    case holo
    /// Textured foil on the frame, artwork left untouched.
    case reverseHolo
    /// Drifting star layers over a nebula, parallax on tilt.
    case cosmos
    /// Deep-space nebula with coloured gas clouds.
    case galaxy
    /// Crossing rainbow gradients, glitter, etched stripes.
    case rainbow
    /// Geometric gold foil with sparkles.
    case gold
    /// Saturated paint-splash foil (amazing rare).
    case amazing
    /// Etched diagonal lattice with sparkles (radiant).
    case radiant
    /// Diffraction-grating rings, CD-like.
    case prism
    /// Pearlescent thin-film iridescence.
    case pearl
    /// Brushed anisotropic metal with a travelling specular band.
    case brushedMetal
    /// Vertical sun-pillar rainbow with diamond-plate etching (full art).
    case fullArt
    /// Wavy interference foil (VMAX style).
    case interference

    public var displayName: String {
        switch self {
        case .matte: "Matte"
        case .holo: "Holo"
        case .reverseHolo: "Reverse holo"
        case .cosmos: "Cosmos"
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

    /// Anything but matte.
    public var isFoil: Bool { self != .matte }

    /// Where the foil is printed on framed templates. Borderless templates
    /// always use `.fullCard` because the artwork is the whole card.
    public var region: FinishRegion {
        switch self {
        case .matte: .fullCard
        case .holo, .cosmos, .amazing: .artwork
        case .reverseHolo: .frame
        case .galaxy, .rainbow, .gold, .radiant, .prism, .pearl, .brushedMetal, .fullArt, .interference: .fullCard
        }
    }
}

/// Region of a framed card covered by a finish.
public enum FinishRegion: String, Hashable, Sendable, Codable {
    case artwork
    case frame
    case fullCard
}
