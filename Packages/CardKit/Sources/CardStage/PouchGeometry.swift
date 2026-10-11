import Foundation
import simd

/// Proportions of a sealed pouch, in stage units: one unit wide.
public enum PouchMetrics {
    public static let width: Float = 1
    public static let height: Float = 1.86
    /// Height of each crimped seal as a fraction of the pouch height.
    public static let seal: Float = 86 / 1904
    /// Vertical position (0…1 from the bottom) of the tear line under the top seal.
    public static let tearLine: Float = 1 - 0.085
    /// Zig-zag teeth across the width of a seal, and their depth (0…1 of the height).
    public static let teeth: Float = 38
    public static let toothDepth: Float = 0.0056
    /// Side notches at the tear line: depth across, half height along.
    public static let notch: SIMD2<Float> = [0.022, 0.014]
    /// The floor the packs stand on.
    public static let floorY: Float = -height / 2 - 0.1
}

/// Vertex of a pouch: position, normal and texture coordinates.
public struct PouchVertex: Sendable {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var uv: SIMD2<Float>
}

/// Triangle mesh of one side of a pouch, pillowed by the cards inside and
/// wrinkled like real foil. Built once per look, off the main actor.
public struct PouchMesh: Sendable {
    public var vertices: [PouchVertex]
    public var indices: [UInt32]

    static let columns = 150
    static let rows = 280

    /// - Parameters:
    ///   - back: the back side carries the longitudinal seam.
    ///   - seed: noise seed so the two sides wrinkle differently.
    ///   - puff: 0…1 how much the cards push the foil out.
    ///   - wrinkles: 0…1 amplitude of the creases.
    public nonisolated static func make(back: Bool, seed: Int32, puff: Float, wrinkles: Float) -> PouchMesh {
        let w = PouchMetrics.width, h = PouchMetrics.height, sealV = PouchMetrics.seal
        let puffAmp = 0.02 + 0.14 * puff
        let wrinkleAmp = 0.0078 * wrinkles
        let shoulder: Float = 0.15
        let cols = columns, rows = rows
        var vertices = [PouchVertex]()
        vertices.reserveCapacity((cols + 1) * (rows + 1))
        let rise: (Float) -> Float = { m in m <= 0 ? 0 : m >= 1 ? 1 : 1 - pow(1 - m, 2.4) }
        let pleat: (Float) -> Float = { m in m <= 0 ? 0 : pow(sin(.pi * min(1, m / 1.3)), 1.4) }
        let tau = Float.pi * 2
        for r in 0...rows {
            let t = Float(r) / Float(rows)
            for c in 0...cols {
                let p = Float(c) / Float(cols)
                // Columns bunch toward the sides, where the foil folds.
                let cx = StageMath.lerp(p, 0.5 - 0.5 * cos(.pi * p), 0.5)
                let f = abs(2 * cx - 1)
                let across = pow(max(0, 1 - pow(f, 3.6)), 0.5)
                let span = shoulder * (1 + 1.1 * f * f)
                let fromBottom = (t - sealV) / span
                let fromTop = (1 - t - sealV) / span
                let along = min(1, (abs(2 * t - 1) / (1 - 2 * sealV)) * (1 + 0.1 * f * f))
                let pillow = pow(max(0, 1 - pow(along, 3)), 0.75) * rise(fromBottom * 1.6) * rise(fromTop * 1.6)
                let bulge = puffAmp * across * pillow * (1 + 0.08 * StageNoise.fbm(cx * 2.3, t * 3.2, seed: seed, octaves: 3))
                let folds: (Int32) -> Float = { s in
                    let n = StageNoise.fbm(cx * 3.5, t * 5, seed: s, octaves: 2)
                    return 0.55 * sin(tau * (cx * 9 + n * 0.9)) + 0.3 * sin(tau * (cx * 17 + n * 1.3 + 0.3)) + 0.15 * sin(tau * (cx * 29 + n * 2))
                }
                var crease = wrinkleAmp * across * (pleat(fromBottom) * folds(seed + 5) + pleat(fromTop) * folds(seed + 9))
                let edgeX = min(cx, 1 - cx)
                let edgeY = min(t, 1 - t) - sealV
                if edgeX < 0.3, edgeY > 0, edgeY < 0.3 {
                    crease += wrinkleAmp * 0.5 * across * sin(tau * (edgeX + edgeY) * 7) * (1 - edgeX / 0.3) * (1 - edgeY / 0.3)
                }
                var z = bulge + max(crease, -0.7 * bulge)
                if back {
                    // Longitudinal seam of the back.
                    z += 0.0034 * (1 - StageMath.smoothstep(0.036, 0.043, abs(cx - 0.5))) * StageMath.smoothstep(-0.004, 0.02, edgeY)
                }
                let x = (cx - 0.5) * w * (1 - 0.062 * pillow * (0.72 + 0.28 * sin(.pi * t)))
                let y = (t - 0.5) * h
                vertices.append(PouchVertex(position: [x, y, z], normal: [0, 0, 1], uv: [cx, t]))
            }
        }
        var indices = [UInt32]()
        indices.reserveCapacity(cols * rows * 6)
        for r in 0..<rows {
            for c in 0..<cols {
                let a = UInt32(r * (cols + 1) + c)
                let b = a + 1
                let d = a + UInt32(cols + 1)
                let e = d + 1
                indices += [a, b, e, a, e, d]
            }
        }
        var mesh = PouchMesh(vertices: vertices, indices: indices)
        mesh.computeNormals()
        return mesh
    }

    /// Area-weighted vertex normals.
    mutating func computeNormals() {
        var sums = [SIMD3<Float>](repeating: .zero, count: vertices.count)
        var i = 0
        while i + 2 < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            let n = cross(vertices[b].position - vertices[a].position, vertices[c].position - vertices[a].position)
            sums[a] += n; sums[b] += n; sums[c] += n
            i += 3
        }
        for v in vertices.indices {
            let s = sums[v]
            vertices[v].normal = length(s) > 0 ? normalize(s) : [0, 0, 1]
        }
    }
}
