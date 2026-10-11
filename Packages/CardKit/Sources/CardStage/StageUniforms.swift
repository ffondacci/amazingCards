import simd

/// Per-frame constants, laid out exactly like `FrameUniforms` in Stage.metal.
struct FrameUniforms {
    var viewProjection: float4x4
    /// xyz camera position.
    var cameraPosition: SIMD4<Float>
    /// xyz direction toward the light, w intensity.
    var lightDirection: SIMD4<Float>
    var lightColor: SIMD4<Float>
    /// time, shine sweep position, night (0/1), floor y.
    var params: SIMD4<Float>
    /// foil, holo, gloss, shine.
    var look: SIMD4<Float>
    /// reflection fade distance, reflection strength, wrinkle scale, 0.
    var reflect: SIMD4<Float>
    /// floor line (fraction of the height from the top), rays opacity, halo opacity, dim opacity.
    var screen: SIMD4<Float> = .zero
    /// premium (0/1), viewport width, viewport height, flash.
    var screen2: SIMD4<Float> = .zero
}

/// One wedge of the light rays behind a revealed card: start angle, width (degrees), peak alpha.
struct RayWedge {
    var start: Float
    var width: Float
    var alpha: Float
    var pad: Float = 0
}

/// Per-draw constants, laid out exactly like `ObjectUniforms` in Stage.metal.
/// A sealed pack on the ring only sets `model` and `flags`; the pieces of
/// a pack being opened drive the rest.
struct ObjectUniforms {
    var model: float4x4
    /// reflect (0/1), side (±1), zig edges (0/1), opacity.
    var flags: SIMD4<Float>
    /// tear line v (2 = none), tear side (0 body, 1 strip), cut progress, inside visible (0/1).
    var tear: SIMD4<Float> = [2, 0, 0, 0]
    /// line mode (0 tear, 2 melt, 3 zip), cut direction (0 →, 1 ←, 2 from the middle), perforation, heat.
    var cut: SIMD4<Float> = .zero
    /// tip glow, dissolve, inner glow, guide line.
    var glow: SIMD4<Float> = .zero
    /// peel mode (0 none, 1 lift, 2 roll, 3 rip), peel direction, peel amount, fly.
    var peel: SIMD4<Float> = [0, 1, 1, 0]
    /// mouth opening, mouth strength, card (0/1), card emissive.
    var mouth: SIMD4<Float> = [0, 1, 0, 0]

    init(model: float4x4, flags: SIMD4<Float>) {
        self.model = model
        self.flags = flags
    }
}
