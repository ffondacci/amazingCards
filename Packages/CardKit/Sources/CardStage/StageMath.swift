import Foundation
import simd

/// Matrices, easings and the critically damped spring every stage motion
/// uses. Metal clip space: y up, z in 0…1.
public enum StageMath {
    public static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let y = 1 / tan(fovY / 2)
        let x = y / aspect
        let z = far / (near - far)
        return float4x4(columns: (
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * near, 0)
        ))
    }

    public static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) -> float4x4 {
        let f = normalize(target - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)
        return float4x4(columns: (
            SIMD4(s.x, u.x, -f.x, 0),
            SIMD4(s.y, u.y, -f.y, 0),
            SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
        ))
    }

    public static func translation(_ t: SIMD3<Float>) -> float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t, 1)
        return m
    }

    public static func scale(_ s: SIMD3<Float>) -> float4x4 {
        float4x4(diagonal: SIMD4(s, 1))
    }

    public static func rotationX(_ a: Float) -> float4x4 {
        let c = cos(a), s = sin(a)
        return float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0), SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)))
    }

    public static func rotationY(_ a: Float) -> float4x4 {
        let c = cos(a), s = sin(a)
        return float4x4(columns: (SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0), SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)))
    }

    public static func rotationZ(_ a: Float) -> float4x4 {
        let c = cos(a), s = sin(a)
        return float4x4(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
    }

    /// Euler rotation in the YXZ order (yaw, then pitch, then roll), the
    /// order the stage uses for every pack.
    public static func rotationYXZ(x: Float, y: Float, z: Float) -> float4x4 {
        rotationY(y) * rotationX(x) * rotationZ(z)
    }

    /// Model matrix from a position, YXZ euler angles and a uniform scale.
    public static func model(position: SIMD3<Float>, euler: SIMD3<Float>, scale s: Float) -> float4x4 {
        translation(position) * rotationYXZ(x: euler.x, y: euler.y, z: euler.z) * scale(SIMD3(repeating: s))
    }

    /// Mirror through the horizontal plane at `y`.
    public static func mirror(y: Float) -> float4x4 {
        translation([0, 2 * y, 0]) * scale([1, -1, 1])
    }

    public static func wrap(_ x: Float, _ m: Float) -> Float {
        ((x.truncatingRemainder(dividingBy: m)) + m).truncatingRemainder(dividingBy: m)
    }

    public static func clamp01(_ x: Float) -> Float { min(1, max(0, x)) }
    public static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    /// 0…1 progress of `x` between `a` and `b`.
    public static func progress(_ x: Float, _ a: Float, _ b: Float) -> Float { clamp01((x - a) / (b - a)) }

    public static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = clamp01((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }
}

/// The easing curves of the stage choreography.
public enum StageEase {
    /// Ease in-out cubic.
    public static func smooth(_ t: Float) -> Float {
        let t = StageMath.clamp01(t)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    public static func outCubic(_ t: Float) -> Float { 1 - pow(1 - StageMath.clamp01(t), 3) }
    public static func inCubic(_ t: Float) -> Float { pow(StageMath.clamp01(t), 3) }
    /// Overshooting pop, for a pack landing in its slot.
    public static func backOut(_ t: Float) -> Float {
        let t = StageMath.clamp01(t)
        let c: Float = 1.70158
        return 1 + (c + 1) * pow(t - 1, 3) + c * pow(t - 1, 2)
    }
}

/// Critically damped spring: `stiffness` pulls toward the target, the
/// damping is derived so the motion never oscillates.
public struct StageSpring: Sendable {
    public static func step(_ x: Float, _ v: Float, target: Float, stiffness k: Float, dt: Float) -> (Float, Float) {
        let damping = 2 * sqrt(k)
        let v2 = v + (k * (target - x) - damping * v) * dt
        return (x + v2 * dt, v2)
    }
}

/// Deterministic value noise shared by the geometry and the normal map.
enum StageNoise {
    static func hash(_ x: Int32, _ y: Int32, _ seed: Int32) -> Float {
        var n = (x &* 374761393) &+ (y &* 668265263) &+ (seed &* 1442695041)
        n = (n ^ (n >> 13)) &* 1274126177
        n = n ^ (n >> 16)
        return Float(UInt32(bitPattern: n)) / 4294967296
    }

    /// Smooth value noise in −1…1.
    static func value(_ x: Float, _ y: Float, seed: Int32 = 0) -> Float {
        let fx = floor(x), fy = floor(y)
        let ix = Int32(fx), iy = Int32(fy)
        let rx = x - fx, ry = y - fy
        let ox = rx * rx * (3 - 2 * rx), oy = ry * ry * (3 - 2 * ry)
        let c = hash(ix, iy, seed), h = hash(ix + 1, iy, seed)
        let f = hash(ix, iy + 1, seed), u = hash(ix + 1, iy + 1, seed)
        return (c + (h - c) * ox + (f - c) * oy + (c - h - f + u) * ox * oy) * 2 - 1
    }

    /// Fractional Brownian motion, `octaves` layers.
    static func fbm(_ x: Float, _ y: Float, seed: Int32 = 0, octaves: Int = 4) -> Float {
        var sum: Float = 0, amp: Float = 0.5, norm: Float = 0
        var px = x, py = y
        for o in 0..<octaves {
            sum += amp * value(px, py, seed: seed + Int32(o) * 17)
            norm += amp
            px = px * 2.03 + 11.7
            py = py * 2.03 + 3.1
            amp *= 0.5
        }
        return sum / norm
    }

    /// Small deterministic generator for the long creases.
    struct Generator {
        private var state: UInt32
        init(seed: UInt32) { state = seed }
        mutating func next() -> Float {
            state = state &+ 1831565813
            var t = state
            t = (t ^ (t >> 15)) &* (t | 1)
            t ^= t &+ (t ^ (t >> 7)) &* (t | 61)
            return Float(t ^ (t >> 14)) / 4294967296
        }
    }
}
