import Foundation
import simd

/// Procedural normal map of crinkled foil: fine ridges on the seals, a
/// groove where the seal ends, pleats under it, and a handful of long
/// creases across the body. 512 × 952 RGBA, +Z up, built off the main actor.
public struct WrinkleNormalMap: Sendable {
    public static let width = 512
    public static let height = 952
    public var rgba: [UInt8]

    public nonisolated static func make() -> WrinkleNormalMap {
        let w = width, h = height
        let sealV = PouchMetrics.seal
        let dx = PouchMetrics.width / Float(w - 1)
        let dy = PouchMetrics.height / Float(h - 1)
        var field = [Float](repeating: 0, count: w * h)
        let tau = Float.pi * 2
        for r in 0..<h {
            let v = Float(r) / Float(h - 1)
            let edge = min(v, 1 - v)
            let half: Int32 = v > 0.5 ? 9 : 0
            let inSeal = 1 - StageMath.smoothstep(sealV - 0.003, sealV + 0.002, edge)
            let inBody = 1 - inSeal
            let past = edge - sealV
            let pleat = past > 0 ? exp(-past / 0.045) : 0
            for c in 0..<w {
                let u = Float(c) / Float(w - 1)
                var t = inSeal * (55e-5 * sin(u * tau * 118) + 5e-4 * StageNoise.fbm(u * 24, v * 30 + Float(half), seed: 5, octaves: 2))
                t -= 0.0011 * exp(-pow((edge - sealV) / 0.0024, 2))
                t += inBody * 42e-5 * StageNoise.fbm(u * 13, v * 22, seed: 9, octaves: 4)
                if pleat > 0.01 {
                    let p = 1 - abs(sin((u * 52 + 2.2 * StageNoise.fbm(u * 3, v * 8 + Float(half), seed: 13, octaves: 2)) * .pi))
                    t += inBody * pleat * 7e-4 * (p * p - 0.35)
                }
                let side = min(u, 1 - u)
                t += inBody * 6e-4 * exp(-pow((side - 0.045) / 0.006, 2))
                field[r * w + c] = t
            }
        }
        // Long creases.
        var gen = StageNoise.Generator(seed: 4)
        for _ in 0..<18 {
            let cx = (0.12 + gen.next() * 0.76) * PouchMetrics.width
            let cy = (sealV + 0.06 + gen.next() * (1 - 2 * sealV - 0.12)) * PouchMetrics.height
            let angle = gen.next() * .pi
            let len = 0.12 + gen.next() * 0.42
            let depth = (gen.next() < 0.55 ? -1 : 1) * (3e-4 + gen.next() * 6e-4)
            let radius = 0.003 + gen.next() * 0.0035
            let x0 = cx - cos(angle) * len / 2, y0 = cy - sin(angle) * len / 2
            let x1 = cx + cos(angle) * len / 2, y1 = cy + sin(angle) * len / 2
            let c0 = max(0, Int(floor((min(x0, x1) - radius * 2) / dx)))
            let c1 = min(w - 1, Int(ceil((max(x0, x1) + radius * 2) / dx)))
            let r0 = max(0, Int(floor((min(y0, y1) - radius * 2) / dy)))
            let r1 = min(h - 1, Int(ceil((max(y0, y1) + radius * 2) / dy)))
            let len2 = len * len
            if c0 > c1 || r0 > r1 { continue }
            for r in r0...r1 {
                for c in c0...c1 {
                    let px = Float(c) * dx, py = Float(r) * dy
                    let s = StageMath.clamp01(((px - x0) * (x1 - x0) + (py - y0) * (y1 - y0)) / len2)
                    let d = hypot(px - (x0 + s * (x1 - x0)), py - (y0 + s * (y1 - y0)))
                    if d < radius {
                        field[r * w + c] += depth * pow(sin(.pi * s), 0.6) * pow(1 - d / radius, 1.6)
                    }
                }
            }
        }
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for r in 0..<h {
            let up = max(r - 1, 0), down = min(r + 1, h - 1)
            for c in 0..<w {
                let left = max(c - 1, 0), right = min(c + 1, w - 1)
                let gx = (field[r * w + right] - field[r * w + left]) / (Float(right - left) * dx)
                let gy = (field[down * w + c] - field[up * w + c]) / (Float(down - up) * dy)
                let n = normalize(SIMD3<Float>(-gx, -gy, 1))
                let i = (r * w + c) * 4
                rgba[i] = UInt8(clamping: Int((n.x * 0.5 + 0.5) * 255))
                rgba[i + 1] = UInt8(clamping: Int((n.y * 0.5 + 0.5) * 255))
                rgba[i + 2] = UInt8(clamping: Int((n.z * 0.5 + 0.5) * 255))
            }
        }
        return WrinkleNormalMap(rgba: rgba)
    }
}
