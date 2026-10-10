import SwiftUI

/// Access point to the Metal library bundled with `CardFX`.
///
/// Every stitchable function is prefixed `ck_`. Build shaders through
/// `CardEffect` rather than by hand so the Swift argument order always matches
/// the Metal signature.
public enum CardFXShaders {
    /// The compiled Metal library (`default.metallib` of this package target).
    public static let library: ShaderLibrary = .bundle(.module)

    /// Names of every stitchable function, used by `warmUp()` and by tests.
    public static let functionNames: [String] = [
        "ck_holo", "ck_glare", "ck_sparkle", "ck_sweep", "ck_holoPaper",
        "ck_foilWrap", "ck_starfield", "ck_nebula", "ck_burst", "ck_shimmer",
        "ck_chromatic", "ck_dissolve", "ck_tear", "ck_ripple", "ck_curl", "ck_sparks",
        "ck_paper", "ck_paperTension", "ck_mouth",
    ]

    static func function(_ name: String) -> ShaderFunction {
        ShaderFunction(library: library, name: name)
    }

    /// Compiles every shader ahead of time so the first card drawn does not
    /// hitch. `first` is compiled before the rest (the effects of the screen
    /// the user reaches first, typically a pack opening). Safe to call
    /// several times; errors are swallowed because a failed pre-compilation
    /// only costs the hitch it tried to avoid.
    public static func warmUp(first: [CardEffect] = []) async {
        let size = CGSize(width: 300, height: 420)
        // The first set compiles in parallel, then the geometry shaders.
        await compile(first, size: size, parallel: true)
        try? await CurlShader.shader(size: size, lineY: 60, front: 100, fromTrailing: false, radius: 20, edgeAllowance: 8)
            .compile(as: .layerEffect)
        try? await TearShader.shader(size: size, origin: .zero, tip: .zero, gap: 0, roughness: 0, lift: 0)
            .compile(as: .layerEffect)
        try? await MouthShader.shader(size: size, open: 1, lineY: 40, depth: 100).compile(as: .distortionEffect)
        // The rest compiles one at a time at low priority: a burst of
        // parallel Metal compilations starves the main thread and shows as
        // dropped frames in whatever the user does meanwhile.
        let rest = CardEffect.showcase.filter { !first.contains($0) }
        await Task(priority: .utility) {
            await compile(rest, size: size, parallel: false)
            try? await CardRippleModifier.shader(size: size, center: .zero, elapsed: 0, amplitude: 1, frequency: 1)
                .compile(as: .distortionEffect)
        }.value
    }

    /// Effects a pack opening draws: compile these first.
    public static let packOpeningEffects: [CardEffect] = [
        .starfield(), .nebula(palette: .violet), .foilWrap(), .glare(), .paper(),
        .sparks(origin: .zero, direction: CGPoint(x: 1, y: 0)),
        .paperTension(point: .zero, front: 0, direction: 1), .burst(),
    ]

    private static func compile(_ effects: [CardEffect], size: CGSize, parallel: Bool) async {
        let idle = CardMotion()
        func compileOne(_ effect: CardEffect) async {
            let shader = effect.shader(motion: idle, size: size)
            switch effect.kind {
            case .color: try? await shader.compile(as: .colorEffect)
            case .layer: try? await shader.compile(as: .layerEffect)
            }
        }
        if parallel {
            await withTaskGroup(of: Void.self) { group in
                for effect in effects {
                    group.addTask { await compileOne(effect) }
                }
            }
        } else {
            for effect in effects {
                guard !Task.isCancelled else { return }
                await compileOne(effect)
                await Task.yield()
            }
        }
    }
}

/// Builder for the scroll roll of a torn strip (`ck_curl`), used by `CardPack`.
public enum CurlShader {
    /// - Parameters:
    ///   - lineY: y of the cut in the layer; the strip is above it.
    ///   - front: torn length from the start edge, in points.
    ///   - fromTrailing: true when the tear started on the trailing edge.
    ///   - radius: radius of the roll, in points (see `rollRadius`).
    ///   - edgeAllowance: how far below `lineY` the jagged edge may reach.
    public static func shader(
        size: CGSize,
        lineY: Double,
        front: Double,
        fromTrailing: Bool,
        radius: Double,
        edgeAllowance: Double
    ) -> Shader {
        Shader(
            function: CardFXShaders.function("ck_curl"),
            arguments: [
                .float2(size), .float(lineY), .float(front),
                .float(fromTrailing ? 1 : 0), .float(radius), .float(edgeAllowance),
            ]
        )
    }

    /// Radius of a loosely rolled strip after `front` points have been torn,
    /// capped by the strip height so the roll never dwarfs the band.
    public static func rollRadius(front: Double, stripHeight: Double) -> Double {
        min(max(stripHeight * 0.3, front / 4.5), stripHeight * 0.85)
    }
}

/// Builder for the bag-mouth distortion (`ck_mouth`) of a torn pack body.
public enum MouthShader {
    public static func shader(size: CGSize, open: Double, lineY: Double, depth: Double) -> Shader {
        Shader(
            function: CardFXShaders.function("ck_mouth"),
            arguments: [.float2(size), .float(open), .float(lineY), .float(depth)]
        )
    }
}

/// Low-level builder for the tear layer effect, shared with `CardPack`.
public enum TearShader {
    public static func shader(
        size: CGSize,
        origin: CGPoint,
        tip: CGPoint,
        gap: Double,
        roughness: Double,
        lift: Double
    ) -> Shader {
        Shader(
            function: CardFXShaders.function("ck_tear"),
            arguments: [
                .float2(size), .float2(origin), .float2(tip),
                .float(gap), .float(roughness), .float(lift),
            ]
        )
    }

    /// Jagged offset of the torn edge at a distance `x` (points) along the cut.
    /// Mirrors `tearNoise` in `Transitions.metal`, multiply by the roughness.
    public static func edgeOffset(at x: Double) -> Double {
        sin(x * 0.31 + 1.3) * 0.45 + sin(x * 0.73 + 2.7) * 0.30
            + sin(x * 1.37 + 0.5) * 0.15 + sin(x * 2.9) * 0.10
    }

    /// Smooth fine-fibre offset (−1…1) at `x` points along the cut. Mirrors
    /// `fibreNoise` in `Transitions.metal`; multiply by 0.45 × roughness.
    public static func fibreOffset(at x: Double) -> Double {
        func smooth(_ f: Double) -> Double { f * f * (3 - 2 * f) }
        let a = x * 0.9, b = x * 2.7
        let ia = floor(a), ib = floor(b)
        let fa = smooth(a - ia), fb = smooth(b - ib)
        let na = hash(ia, 3) + (hash(ia + 1, 3) - hash(ia, 3)) * fa
        let nb = hash(ib, 9) + (hash(ib + 1, 9) - hash(ib, 9)) * fb
        return (na * 2 - 1) * 0.7 + (nb * 2 - 1) * 0.3
    }

    /// Mirrors `hash21` of the Metal sources (0…1), used for the fine fibres.
    public static func hash(_ x: Double, _ y: Double) -> Double {
        func fract(_ v: Double) -> Double { v - floor(v) }
        var p0 = fract(x * 0.1031), p1 = fract(y * 0.1031), p2 = fract(x * 0.1031)
        let d = p0 * (p1 + 33.33) + p1 * (p2 + 33.33) + p2 * (p0 + 33.33)
        p0 += d; p1 += d; p2 += d
        return fract((p0 + p1) * p2)
    }
}
