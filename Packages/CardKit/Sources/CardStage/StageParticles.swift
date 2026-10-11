import Foundation
import simd

/// Flakes of foil, sparks and smoke flying around an opening: simulated
/// on the CPU every frame, drawn as instances. Pools are fixed so nothing
/// allocates while the pack opens.
struct StageParticles: Sendable {
    struct Flake: Sendable {
        var position = SIMD3<Float>.zero
        var velocity = SIMD3<Float>.zero
        var rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        var spin = SIMD3<Float>.zero
        var size: Float = 0
        var life: Float = 0
        var max: Float = 1
        var phase: Float = 0
        var color = SIMD3<Float>(repeating: 1)
    }
    struct Spark: Sendable {
        var position = SIMD3<Float>.zero
        var velocity = SIMD3<Float>.zero
        var life: Float = 0
        var max: Float = 1
        var color = SIMD3<Float>(repeating: 1)
    }
    struct Puff: Sendable {
        var position = SIMD3<Float>.zero
        var velocity = SIMD3<Float>.zero
        var life: Float = 0
        var max: Float = 1
        var size: Float = 0
        var spin: Float = 0
        var angle: Float = 0
    }

    static let flakeCount = 360
    static let sparkCount = 260
    static let puffCount = 60

    var flakes = [Flake](repeating: Flake(), count: flakeCount)
    var sparks = [Spark](repeating: Spark(), count: sparkCount)
    var puffs = [Puff](repeating: Puff(), count: puffCount)
    private var nextFlake = 0
    private var nextSpark = 0
    private var nextPuff = 0
    private var clock: Float = 0
    private var rng = SystemRandomNumberGenerator()

    static let foil = SIMD3<Float>(0.949, 0.949, 0.973)
    static let foilLight = simd_mix(SIMD3<Float>(repeating: 1), foil, SIMD3<Float>(repeating: 0.35))
    static let warm: [SIMD3<Float>] = [[1, 0.86, 0.45], [1, 0.97, 0.8], [1, 0.62, 0.25], [0.7, 0.9, 1]]
    static let gold: [SIMD3<Float>] = [[1, 0.84, 0.36], [1, 0.95, 0.7], [1, 0.7, 0.2], [1, 1, 0.9]]
    static let burstFlakes: [SIMD3<Float>] = [[1, 0.949, 0.722], [1, 0.839, 0.42], [0.878, 0.647, 0.149], [1, 1, 1]]

    private mutating func random() -> Float { Float.random(in: 0..<1, using: &rng) }

    /// How many to spawn for a fractional amount, scaled by the dial.
    mutating func count(_ amount: Float, dial: Float) -> Int {
        let a = amount * max(0, dial)
        let whole = Int(a.rounded(.down))
        return whole + (random() < a - Float(whole) ? 1 : 0)
    }

    mutating func spawnFlake(at p: SIMD3<Float>, velocity v: SIMD3<Float>, size: Float, color: SIMD3<Float>, life: Float) {
        let i = nextFlake % Self.flakeCount
        nextFlake += 1
        var f = Flake()
        f.position = p
        f.velocity = v
        f.rotation = StageScene.quaternion(euler: [random() * 6, random() * 6, random() * 6])
        f.spin = SIMD3(random() - 0.5, random() - 0.5, random() - 0.5) * 22
        f.size = size
        f.life = life
        f.max = life
        f.phase = random() * 6
        f.color = color
        flakes[i] = f
    }

    /// A flake torn off the foil at `p`.
    mutating func flake(at p: SIMD3<Float>, scale: Float = 1) {
        spawnFlake(
            at: p + SIMD3((random() - 0.5) * 0.02, (random() - 0.3) * 0.02, 0.01),
            velocity: SIMD3((random() - 0.35) * 0.4, 0.15 + random() * 0.5, 0.15 + random() * 0.35),
            size: (0.009 + random() * random() * 0.024) * scale,
            color: random() < 0.72 ? Self.foil : Self.foilLight,
            life: 1.1 + random() * 0.9
        )
    }

    mutating func spawnSparks(at p: SIMD3<Float>, count n: Int, spread: SIMD3<Float>, speed: Float, lift: Float = 0.6, gold: Bool = false) {
        for _ in 0..<n {
            let i = nextSpark % Self.sparkCount
            nextSpark += 1
            let a = random() * 2 * .pi
            let t = acos(2 * random() - 1)
            let s = speed * (0.35 + random() * 0.65)
            var k = Spark()
            k.position = p + SIMD3((random() - 0.5) * spread.x, (random() - 0.5) * spread.y, (random() - 0.5) * spread.z)
            k.velocity = SIMD3(cos(a) * sin(t) * s, cos(t) * s * 0.6 + lift * s, sin(a) * sin(t) * s * 0.5)
            k.life = 0.45 + random() * 0.7
            k.max = k.life
            let palette = gold ? Self.gold : Self.warm
            k.color = palette[Int(random() * Float(palette.count)) % palette.count]
            sparks[i] = k
        }
    }

    mutating func puff(at p: SIMD3<Float>) {
        let i = nextPuff % Self.puffCount
        nextPuff += 1
        var q = Puff()
        q.position = p
        q.velocity = SIMD3((random() - 0.5) * 0.12, 0.22 + random() * 0.22, 0.04 + random() * 0.1)
        q.life = 1.3 + random() * 0.9
        q.max = q.life
        q.size = 0.05 + random() * 0.05
        q.spin = (random() - 0.5) * 1.2
        q.angle = random() * 2 * .pi
        puffs[i] = q
    }

    mutating func update(_ dt: Float) {
        clock += dt
        for i in flakes.indices where flakes[i].life > 0 {
            var f = flakes[i]
            f.life -= dt
            f.velocity.y -= 1.5 * dt
            f.velocity *= exp(-dt * 2.2)
            f.velocity.x += sin(clock * 5 + f.phase) * 0.9 * dt
            f.position += f.velocity * dt
            f.rotation = f.rotation * StageScene.quaternion(euler: f.spin * dt)
            flakes[i] = f
        }
        let drag = pow(0.985, dt * 60)
        for i in sparks.indices where sparks[i].life > 0 {
            var k = sparks[i]
            k.life -= dt
            k.velocity.y -= 2.4 * dt
            k.velocity *= drag
            k.position += k.velocity * dt
            sparks[i] = k
        }
        for i in puffs.indices where puffs[i].life > 0 {
            var q = puffs[i]
            q.life -= dt
            q.velocity.x *= exp(-dt * 0.8)
            q.position += q.velocity * dt
            q.angle += q.spin * dt
            puffs[i] = q
        }
    }

    /// Current size of a flake (they shrink out at the end).
    static func scale(of f: Flake) -> Float {
        f.life > 0 ? f.size * min(1, f.life / 0.3) : 0
    }

    static func alpha(of k: Spark) -> Float {
        k.life > 0 ? pow(min(1, max(0, k.life / k.max)), 1.3) : 0
    }

    /// Size and opacity of a smoke puff.
    static func look(of q: Puff) -> (size: Float, opacity: Float) {
        guard q.life > 0 else { return (0, 0) }
        let age = 1 - q.life / q.max
        return (q.size + age * 0.42, 0.55 * sin(.pi * min(1, age * 1.15)) * (1 - age * 0.5))
    }
}
