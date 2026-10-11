import Foundation
import simd

/// Light rig and room around the packs.
public enum StageLighting: String, Hashable, Sendable, CaseIterable {
    /// Bright white studio, soft panels, light floor.
    case studio
    /// Dark room with coloured panels.
    case night
}

/// How a pack comes open.
public enum OpeningStyle: String, Hashable, Sendable, CaseIterable, Identifiable {
    /// Swipe across the top to tear the strip off.
    case tear
    /// Swipe out from the middle to rip the strip in two.
    case rip
    /// Pull the tab across to unzip the top.
    case zip
    /// Swipe across the top to melt it open.
    case melt
    /// Swipe across the top to roll it open.
    case roll
    /// Swipe across the top and flip the lid open.
    case lid

    public var id: String { rawValue }

    /// What the finger does.
    public var hint: String {
        switch self {
        case .tear: "Swipe across the top to tear it open"
        case .rip: "Swipe out from the middle to rip it in two"
        case .zip: "Pull the tab across to unzip the top"
        case .melt: "Swipe across the top to melt it open"
        case .roll: "Swipe across the top to roll it open"
        case .lid: "Swipe across the top and flip the lid open"
        }
    }
}

/// Everything about the stage that is a dial: the carousel, the camera,
/// the foil look, the ambiance and the opening. Values are the ones that
/// look right by default; each maps to one MetalForge Booster parameter.
public struct StageSettings: Hashable, Sendable {
    /// How the front pack opens.
    public var opening: OpeningStyle
    /// Speed of the opening choreography (0.4 … 2).
    public var speed: Float
    /// How low the pack is held while it is being opened (0 … 0.5 of the view).
    public var hold: Float
    /// Seconds before an untouched pack opens by itself, 0 = never.
    public var autoOpen: Float
    /// Keep the last card face down and reveal it with a burst.
    public var rareLast: Bool
    /// Show the swipe guide on a pack waiting to be opened.
    public var guide: Bool
    /// Show the hint texts.
    public var hints: Bool
    /// Amount of flakes and sparks (0 … 2).
    public var particles: Float
    /// Light rays behind a presented card.
    public var rays: Bool
    /// Packs on the carousel ring (3…9).
    public var packs: Int
    /// Ring radius multiplier.
    public var spacing: Float
    /// How far the side packs recede (0 flat … 1.6 deep).
    public var depth: Float
    /// Vertical field of view, degrees.
    public var fov: Float
    /// How much the packs turn toward the pointer or the device tilt (0 none … 2).
    public var tilt: Float
    /// Gentle idle sway of the packs.
    public var floats: Bool
    /// Strength of the floor reflection (0…2).
    public var reflection: Float
    /// Strength of the floor shadow (0…2).
    public var shadow: Float
    public var lighting: StageLighting
    /// Draw the room background (false = transparent, the host shows through).
    public var background: Bool
    /// How much the cards inside push the foil out (0…1).
    public var puff: Float
    /// Amplitude of the creases (0…1).
    public var wrinkles: Float
    /// Metal of the print (0 matte … 1 full foil).
    public var foil: Float
    /// Rainbow shift of the foil (0 … 1.5).
    public var holo: Float
    /// Laminate clear coat (0 … 1).
    public var gloss: Float
    /// Brightness of the periodic shine sweep (0 … 1.5).
    public var shine: Float

    public init(
        packs: Int = 5, spacing: Float = 1, depth: Float = 0.82, fov: Float = 28,
        tilt: Float = 1, floats: Bool = true, reflection: Float = 1, shadow: Float = 1,
        lighting: StageLighting = .studio, background: Bool = true,
        puff: Float = 0.55, wrinkles: Float = 0.5, foil: Float = 1, holo: Float = 1,
        gloss: Float = 0.8, shine: Float = 0.55,
        opening: OpeningStyle = .tear, speed: Float = 1, hold: Float = 0.3, autoOpen: Float = 6,
        rareLast: Bool = true, guide: Bool = true, hints: Bool = true, particles: Float = 1, rays: Bool = true
    ) {
        self.opening = opening
        self.speed = speed
        self.hold = hold
        self.autoOpen = autoOpen
        self.rareLast = rareLast
        self.guide = guide
        self.hints = hints
        self.particles = particles
        self.rays = rays
        self.packs = min(9, max(3, packs))
        self.spacing = spacing
        self.depth = depth
        self.fov = fov
        self.tilt = tilt
        self.floats = floats
        self.reflection = reflection
        self.shadow = shadow
        self.lighting = lighting
        self.background = background
        self.puff = puff
        self.wrinkles = wrinkles
        self.foil = foil
        self.holo = holo
        self.gloss = gloss
        self.shine = shine
    }

    public static let standard = StageSettings()
}
