import CardCore
import SwiftUI

/// One shader pass. Compose several with `cardEffect(_:)`:
///
/// ```swift
/// artwork
///     .cardEffect(.holo(.cosmos))
///     .cardEffect(.glare())
/// ```
///
/// Effects read `CardMotion` from the environment, so they must sit inside a
/// `cardMotion(...)` provider (or a `CardMotionStage`) to react to the user.
public enum CardEffect: Hashable, Sendable {
    /// Multi-style foil, see `HoloStyle`.
    case holo(HoloStyle, intensity: Double = 1)
    /// Soft specular highlight under the finger.
    case glare(intensity: Double = 0.55, radius: Double = 0.9)
    /// Twinkling glitter. `density` is the grid size, higher = smaller sparkles.
    case sparkle(intensity: Double = 0.8, density: Double = 32)
    /// One light band at `progress` (0…1). Animate with `cardSweep(progress:)`.
    case sweep(progress: Double, intensity: Double = 0.7, width: Double = 0.16, angle: Double = 35)
    /// Loading shimmer travelling at a fixed pace.
    case shimmer(intensity: Double = 0.6, angle: Double = 20)
    /// Pastel cloudy paper, the printed background of framed cards.
    case holoPaper(hue: Double = 0.55, intensity: Double = 1)
    /// Crinkled metallic wrapper for booster packs.
    case foilWrap(hue: Double = 0.62, intensity: Double = 1)
    /// Deep-space star field generator.
    case starfield(density: Double = 40, intensity: Double = 1)
    /// Coloured gas clouds generator.
    case nebula(palette: NebulaPalette = .violet, intensity: Double = 1)
    /// Rotating ray burst, transparent outside the rays.
    case burst(tint: CardColor = .gold, intensity: Double = 1)
    /// RGB split along the tilt, `amount` in points.
    case chromatic(amount: Double = 6)
    /// Noise dissolve, `progress` 0 = intact, 1 = gone.
    case dissolve(progress: Double, edgeWidth: Double = 0.08, edgeColor: CardColor = .gold, scale: Double = 6)
    /// Sparks at a cutting point (local points), thrown opposite to `direction`.
    case sparks(origin: CGPoint, direction: CGPoint, tint: CardColor = .gold, intensity: Double = 1, life: Double = 0.45)
    /// Lit paper wrapper: folds, wrinkles, crimp bumps (`crimp` points tall
    /// at the top and bottom) and the `bulge` (0…1) of the cards inside.
    case paper(bulge: Double = 1, crimp: Double = 0, intensity: Double = 1)
    /// Paper tension under a finger at `point` (local points), with ripples
    /// ahead of a cut at x = `front` running towards `direction` (±1).
    case paperTension(point: CGPoint, front: Double, direction: Double, strength: Double = 1)

    /// How the pass samples: `color` reads one pixel, `layer` samples around it.
    public enum Kind: Sendable {
        case color
        case layer
    }

    public var kind: Kind {
        switch self {
        case .chromatic, .paper: .layer
        default: .color
        }
    }

    /// True when the look changes over time even with a still card.
    public var isTimeDriven: Bool {
        switch self {
        case .holo(let style, _): style.isTimeDriven
        case .sparkle, .shimmer, .starfield, .nebula, .burst, .sparks, .paperTension: true
        case .glare, .sweep, .holoPaper, .foilWrap, .chromatic, .dissolve, .paper: false
        }
    }

    /// Largest sampling distance for layer effects (points).
    var maxSampleOffset: CGSize {
        switch self {
        case .chromatic(let amount): CGSize(width: amount, height: amount)
        case .paper: CGSize(width: 8, height: 8)
        default: .zero
        }
    }

    public var displayName: String {
        switch self {
        case .holo(let style, _): style.displayName
        case .glare: "Glare"
        case .sparkle: "Sparkle"
        case .sweep: "Light sweep"
        case .shimmer: "Shimmer"
        case .holoPaper: "Holo paper"
        case .foilWrap: "Foil wrapper"
        case .starfield: "Star field"
        case .nebula(let palette, _): "Nebula · \(palette.displayName)"
        case .burst: "Burst"
        case .chromatic: "Chromatic split"
        case .dissolve: "Dissolve"
        case .sparks: "Sparks"
        case .paper: "Paper"
        case .paperTension: "Paper tension"
        }
    }

    public var summary: String {
        switch self {
        case .holo(let style, _): style.summary
        case .glare: "Specular highlight following the finger or the tilt."
        case .sparkle: "Twinkling glitter, brighter on light pixels."
        case .sweep: "A light band crossing the card, animatable."
        case .shimmer: "Placeholder shimmer while artwork loads."
        case .holoPaper: "Printed pastel background of framed cards."
        case .foilWrap: "Metallic crinkled wrapper of a booster pack."
        case .starfield: "Procedural stars with parallax on tilt."
        case .nebula: "Drifting gas clouds, four palettes."
        case .burst: "Ray burst behind a revealed rare card."
        case .chromatic: "RGB split along the tilt direction."
        case .dissolve: "Noise dissolve with a glowing edge, animatable."
        case .sparks: "Hot core, ember trail, flying sparks and paper flecks at a cut."
        case .paper: "Folds, wrinkles and crimps lit by the tilt, with the bulge of the cards inside."
        case .paperTension: "Dent and wrinkles under the finger, ripples ahead of the cut."
        }
    }

    /// One representative of each effect, for catalogs and shader warm-up.
    public static let showcase: [CardEffect] =
        HoloStyle.allCases.map { CardEffect.holo($0) } + [
            .glare(), .sparkle(), .sweep(progress: 0.5), .shimmer(), .holoPaper(), .foilWrap(),
            .starfield(), .nebula(palette: .violet), .nebula(palette: .teal), .nebula(palette: .ember),
            .nebula(palette: .emerald), .burst(), .chromatic(), .dissolve(progress: 0.3),
            .sparks(origin: CGPoint(x: 150, y: 60), direction: CGPoint(x: 1, y: 0)),
            .paper(bulge: 1, crimp: 14),
            .paperTension(point: CGPoint(x: 150, y: 60), front: 150, direction: 1),
        ]

    /// True for generators that replace their source (draw them over an opaque shape).
    public var isGenerator: Bool {
        switch self {
        case .holoPaper, .starfield, .nebula, .burst, .sparks, .paperTension: true
        default: false
        }
    }

    // MARK: Shader construction

    /// Builds the SwiftUI `Shader` for this pass. Argument order is the
    /// contract with the Metal source: size, tilt, pointer, time, then the
    /// effect parameters.
    public func shader(motion: CardMotion, size: CGSize) -> Shader {
        let common: [Shader.Argument] = [
            .float2(size),
            .float2(motion.tilt),
            .float2(motion.pointerArgument),
            .float(motion.time),
        ]
        switch self {
        case .holo(let style, let intensity):
            return make("ck_holo", common + [.float(intensity), .float(Double(style.rawValue))])
        case .glare(let intensity, let radius):
            return make("ck_glare", common + [.float(intensity), .float(radius)])
        case .sparkle(let intensity, let density):
            return make("ck_sparkle", common + [.float(intensity), .float(density)])
        case .sweep(let progress, let intensity, let width, let angle):
            return make("ck_sweep", common + [.float(intensity), .float(progress), .float(width), .float(angle)])
        case .shimmer(let intensity, let angle):
            return make("ck_shimmer", common + [.float(intensity), .float(angle)])
        case .holoPaper(let hue, let intensity):
            return make("ck_holoPaper", common + [.float(intensity), .float(hue)])
        case .foilWrap(let hue, let intensity):
            return make("ck_foilWrap", common + [.float(intensity), .float(hue)])
        case .starfield(let density, let intensity):
            return make("ck_starfield", common + [.float(intensity), .float(density)])
        case .nebula(let palette, let intensity):
            return make("ck_nebula", common + [.float(intensity), .float(Double(palette.rawValue))])
        case .burst(let tint, let intensity):
            return make("ck_burst", common + [.float(intensity), .float3(tint.red, tint.green, tint.blue)])
        case .chromatic(let amount):
            return make("ck_chromatic", [.float2(size), .float2(motion.tilt), .float(amount)])
        case .sparks(let origin, let direction, let tint, let intensity, let life):
            return make("ck_sparks", [
                .float2(size), .float2(origin), .float2(direction), .float(motion.time),
                .float(intensity), .float3(tint.red, tint.green, tint.blue), .float(life),
            ])
        case .paper(let bulge, let crimp, let intensity):
            return make("ck_paper", common + [.float(intensity), .float(bulge), .float(crimp)])
        case .paperTension(let point, let front, let direction, let strength):
            return make("ck_paperTension", [
                .float2(size), .float2(point), .float(front), .float(direction), .float(strength), .float(motion.time),
            ])
        case .dissolve(let progress, let edgeWidth, let edgeColor, let scale):
            return make("ck_dissolve", [
                .float2(size), .float(progress), .float(edgeWidth),
                .float3(edgeColor.red, edgeColor.green, edgeColor.blue), .float(scale),
            ])
        }
    }

    private func make(_ name: String, _ arguments: [Shader.Argument]) -> Shader {
        Shader(function: CardFXShaders.function(name), arguments: arguments)
    }
}

// MARK: - View modifier

private struct CardEffectModifier: ViewModifier {
    let effect: CardEffect
    let isEnabled: Bool
    @Environment(\.cardMotion) private var motion

    func body(content: Content) -> some View {
        switch effect.kind {
        case .color:
            content.visualEffect { [effect, motion, isEnabled] view, proxy in
                view.colorEffect(effect.shader(motion: motion, size: proxy.size), isEnabled: isEnabled)
            }
        case .layer:
            content.visualEffect { [effect, motion, isEnabled] view, proxy in
                view.layerEffect(
                    effect.shader(motion: motion, size: proxy.size),
                    maxSampleOffset: effect.maxSampleOffset,
                    isEnabled: isEnabled
                )
            }
        }
    }
}

public extension View {
    /// Applies one shader pass driven by the environment `cardMotion`.
    func cardEffect(_ effect: CardEffect, isEnabled: Bool = true) -> some View {
        modifier(CardEffectModifier(effect: effect, isEnabled: isEnabled))
    }

    /// Applies several passes in order (first element is applied first).
    func cardEffects(_ effects: [CardEffect], isEnabled: Bool = true) -> some View {
        modifier(CardEffectsModifier(effects: effects, isEnabled: isEnabled))
    }
}

private struct CardEffectsModifier: ViewModifier {
    let effects: [CardEffect]
    let isEnabled: Bool

    func body(content: Content) -> some View {
        // Up to four passes cover every finish recipe; more would hurt frame time anyway.
        content
            .modifier(OptionalEffect(effect: effects.count > 0 ? effects[0] : nil, isEnabled: isEnabled))
            .modifier(OptionalEffect(effect: effects.count > 1 ? effects[1] : nil, isEnabled: isEnabled))
            .modifier(OptionalEffect(effect: effects.count > 2 ? effects[2] : nil, isEnabled: isEnabled))
            .modifier(OptionalEffect(effect: effects.count > 3 ? effects[3] : nil, isEnabled: isEnabled))
    }
}

private struct OptionalEffect: ViewModifier {
    let effect: CardEffect?
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.modifier(CardEffectModifier(effect: effect ?? .glare(intensity: 0), isEnabled: isEnabled && effect != nil))
    }
}
