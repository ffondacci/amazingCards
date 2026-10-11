import CoreGraphics
import Foundation
import Observation
import simd

/// Where one pack stands this frame, ready for the renderer.
public struct PackPose: Sendable {
    public var model: float4x4
    public var position: SIMD3<Float> = .zero
    public var euler: SIMD3<Float> = .zero
    public var scale: Float
    public var visible: Bool
    public var shadowModel: float4x4
    public var shadowOpacity: Float
}

/// What the stage is doing with the front pack.
public enum StagePhase: String, Sendable {
    case idle, zoom, ready, cut, open, present, fan, exit
}

/// Pictures of one card dealt out of a pack.
public struct CardSkin: Identifiable, Sendable {
    public var id: String
    public var front: CGImage
    public var back: CGImage
    /// Foil mask (red = foil, green = holo, blue = matte); nil = laminated print.
    public var mask: CGImage?

    public init(id: String, front: CGImage, back: CGImage, mask: CGImage? = nil) {
        self.id = id
        self.front = front
        self.back = back
        self.mask = mask
    }
}

/// Where a card stands in the opened pack's frame.
struct CardPose: Sendable {
    var x: Float = 0, y: Float = 0, z: Float = 0
    var rx: Float = 0, ry: Float = 0, rz: Float = 0
    var s: Float = 1

    static func mix(_ a: CardPose, _ b: CardPose, _ t: Float) -> CardPose {
        CardPose(
            x: StageMath.lerp(a.x, b.x, t), y: StageMath.lerp(a.y, b.y, t), z: StageMath.lerp(a.z, b.z, t),
            rx: StageMath.lerp(a.rx, b.rx, t), ry: StageMath.lerp(a.ry, b.ry, t), rz: StageMath.lerp(a.rz, b.rz, t),
            s: StageMath.lerp(a.s, b.s, t)
        )
    }

    var model: float4x4 {
        StageMath.model(position: [x, y, z], euler: [rx, ry, rz], scale: s)
    }
}

/// The dials of one piece of the pack being opened, for the shader.
struct PieceDials: Sendable {
    var tearV: Float = 2, tearSide: Float = 0, cutP: Float = 0, inside: Float = 0
    var lineMode: Float = 0, cutDir: Float = 0, perf: Float = 0, heat: Float = 0
    var tipGlow: Float = 0, dissolve: Float = 0, innerGlow: Float = 0, guide: Float = 0
    var peel: Float = 0, peelDir: Float = 1, peelAmt: Float = 1, fly: Float = 0
    var mouth: Float = 0, mouthK: Float = 1
}

/// Everything the renderer needs to draw the pack being opened.
struct OpeningPose: Sendable {
    struct CardDraw: Sendable {
        var model: float4x4
        var order: Int
        var emissive: Float
        var faceDown: Bool
    }
    var visible = false
    var bodyVisible = false
    var bodyModel = matrix_identity_float4x4
    var body = PieceDials()
    var stripVisible = false
    var stripModel = matrix_identity_float4x4
    var strip = PieceDials()
    /// The pull tab of a zip opening, riding the strip at the cut.
    var tabVisible = false
    var tabModel = matrix_identity_float4x4
    var cards: [CardDraw] = []
    /// Light rays and glow behind the rare card: position, scale, opacity.
    var auraOpacity: Float = 0
    /// Flash of the reveal, 0…1.
    var auraPulse: Float = 0
    /// Light rays and halo behind everything, dim of the edges, premium look.
    var raysOpacity: Float = 0
    var dimOpacity: Float = 0
    var premium = false
}

/// State of the opening, from the tap to the fan of cards.
struct OpeningState: Sendable {
    struct Card: Sendable {
        var dealtAt: Float = -1
        var direction: Float = 1
    }
    var phase: StagePhase = .idle
    var style: OpeningStyle = .tear
    var pack = 0
    var t: Float = 0
    var tau: Float = 0
    var cut: Float = 0
    var manual = false
    var top = 0
    var jolt: Float = 0
    var flakeAcc: Float = 0
    var smokeAcc: Float = 0
    var fanAt: Float = 0
    var peek: Float = 0
    var premAt: Float = 0
    var revealAt: Float = 0
    var burst = false
    var aura: Float = 0
    var low: Float = 1
    var rare = true
    var openings = 0
    var cards = [Card](repeating: Card(), count: 5)
    var from = SIMD3<Float>.zero
    var fromRotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var fromScale: Float = 1
    var position = SIMD3<Float>.zero
    var rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var scale: Float = 1
    var exitFrom: StagePhase = .idle
    var exitAt: Float = 0
    var exitT0: Float = 0
    var unopened = false
    var exitPosition = SIMD3<Float>.zero
    var exitRotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var exitScale: Float = 1
    var guide: Float = 0
}

/// Camera of the stage.
public struct StageCamera: Sendable {
    public var position: SIMD3<Float> = [0, 0.26, 6.4]
    public var target: SIMD3<Float> = [0, -0.2, -0.4]
    public var fovY: Float = 28 * .pi / 180
    public var aspect: Float = 1
    public var view: float4x4 = matrix_identity_float4x4
    public var projection: float4x4 = matrix_identity_float4x4
    public var viewProjection: float4x4 { projection * view }
}

/// The carousel of sealed packs: their ring, their springs, the pointer
/// and the gestures. `advance(by:)` moves everything one frame and leaves
/// the poses for the renderer. Main actor, like the view that drives it.
@MainActor @Observable
public final class StageScene {
    public struct Pack: Sendable {
        public var index: Int
        /// 0…1 landing animation when the pack appears.
        public var pop: Float = 1
        public var spinYaw: Float = 0
        public var spinVelocity: Float = 0
        public var spinTarget: Float = 0
        public var spinPitch: Float = 0
        public var spinPitchVelocity: Float = 0
    }

    public var settings: StageSettings {
        didSet {
            if settings.packs != packs.count { rebuildPacks(popping: true) }
            if settings.fov != oldValue.fov || settings.spacing != oldValue.spacing { layoutCamera() }
        }
    }
    public internal(set) var packs: [Pack] = []
    public private(set) var poses: [PackPose] = []
    public private(set) var camera = StageCamera()
    public internal(set) var viewport: SIMD2<Float> = [1, 1]
    public private(set) var time: Float = 0
    /// Position of the shine sweep across the foil, 9 = no sweep.
    public private(set) var sweep: Float = 9
    /// Called when the front pack is tapped: return the cards to deal, or nil to leave it sealed.
    public var onOpen: ((Int) -> [CardSkin]?)?
    /// Called whenever the phase changes.
    public var onPhase: ((StagePhase) -> Void)?
    /// What the stage is doing.
    public var phase: StagePhase { opening.phase }
    /// Text to show the person, nil for none.
    public internal(set) var hint: String?
    /// Cards of the pack being opened, as handed by `onOpen`.
    public internal(set) var dealtCards: [CardSkin] = []
    /// Cards likely to be dealt next: their pictures are uploaded while
    /// the carousel idles, so the opening starts without a hitch.
    public var preparedCards: [CardSkin] = []
    var opening = OpeningState()
    var openingPose = OpeningPose()
    var exitDrop: Float = 0
    var raysLevel: Float = 0
    var dimLevel: Float = 0
    var particles = StageParticles()
    /// Time of the last burst (rare reveal), for the flash overlay.
    public internal(set) var burstTime: TimeInterval?
    /// Set to receive the next rendered frame as a picture (for validation
    /// on a device without a screenshot tool). Needs `StageView(capturable: true)`.
    public var captureRequest: ((CGImage) -> Void)?
    /// Where the floor line is on screen, as a fraction of the height from the top.
    var floorLine: Float {
        let p = camera.viewProjection * SIMD4<Float>(0, PouchMetrics.floorY, 0, 1)
        guard p.w > 0 else { return 0.72 }
        return 0.5 - (p.y / p.w) * 0.5
    }
    var sweepStart: Float = 0.8
    var lastPhase: StagePhase = .idle

    // Carousel.
    var angle: Float = 0
    var velocity: Float = 0
    var target: Float = 0
    var radius: Float = 2
    var away: Float = 0
    // Tilt: pointer while hovering, device otherwise.
    var pointer: SIMD2<Float> = .zero
    var pointerActive = false
    var deviceTilt: SIMD2<Float> = .zero
    var tilt: SIMD2<Float> = .zero

    struct Drag {
        var start: CGPoint
        var last: CGPoint
        var startTime: TimeInterval
        var lastTime: TimeInterval
        var moved: CGFloat = 0
        var speed: Float = 0
        var spinning: Int?
    }
    var drag: Drag?

    public init(settings: StageSettings = .standard) {
        self.settings = settings
        rebuildPacks(popping: false)
        layoutCamera()
    }

    /// Index of the pack facing the camera.
    public var frontIndex: Int { Int(StageMath.wrap(target.rounded(), Float(packs.count))) }

    // MARK: - Frame

    public func advance(by dt: Float) {
        let dt = min(dt, 0.05)
        time += dt
        settleSpins(dt)
        if drag?.spinning == nil, drag == nil {
            (angle, velocity) = StageSpring.step(angle, velocity, target: target, stiffness: 36, dt: dt)
        }
        let busy = opening.phase != .idle && opening.phase != .exit
        away += ((busy ? 1 : 0) - away) * (1 - exp(-dt * 5))
        let wanted: SIMD2<Float> = pointerActive && drag == nil ? pointer : deviceTilt
        tilt += (wanted - tilt) * (1 - exp(-dt * 4))
        if abs(target) > 1000 {
            let turns = (target / Float(packs.count)).rounded() * Float(packs.count)
            target -= turns
            angle -= turns
        }
        let phase = StageMath.wrap(time - sweepStart, 6.5) / 1.6
        sweep = time >= sweepStart && phase < 1 ? StageMath.lerp(-1.45, 1.45, phase * phase * (3 - 2 * phase)) : 9
        placePacks(dt)
        stepOpening(dt)
        raysLevel += (openingPose.raysOpacity - raysLevel) * (1 - exp(-dt * 2.2))
        dimLevel += (openingPose.dimOpacity - dimLevel) * (1 - exp(-dt * 3.3))
        particles.update(dt)
        if opening.phase != lastPhase {
            lastPhase = opening.phase
            onPhase?(opening.phase)
        }
    }

    private func settleSpins(_ dt: Float) {
        for i in packs.indices where drag?.spinning != i {
            var p = packs[i]
            (p.spinYaw, p.spinVelocity) = StageSpring.step(p.spinYaw, p.spinVelocity, target: p.spinTarget, stiffness: 14, dt: dt)
            (p.spinPitch, p.spinPitchVelocity) = StageSpring.step(p.spinPitch, p.spinPitchVelocity, target: 0, stiffness: 26, dt: dt)
            if abs(p.spinYaw - p.spinTarget) < 1e-4, abs(p.spinVelocity) < 0.001 {
                let turns = (p.spinTarget / (2 * .pi)).rounded() * 2 * .pi
                p.spinYaw -= turns
                p.spinTarget -= turns
            }
            packs[i] = p
        }
    }

    private func placePacks(_ dt: Float) {
        let n = packs.count
        let step = 2 * Float.pi / Float(n)
        let night = settings.lighting == .night
        var out = [PackPose]()
        out.reserveCapacity(n)
        for q in 0..<n {
            var p = packs[q]
            var slot = Float(q) - angle
            slot = StageMath.wrap(slot + Float(n) / 2, Float(n)) - Float(n) / 2
            let theta = slot * step
            let near = max(0, 1 - abs(slot))
            let ring = radius * (1 + 2.4 * away * away)
            let x = sin(theta) * ring
            let z = (cos(theta) - 1) * ring * settings.depth - away * 1.6
            var y = -away * 0.3
            var yaw = theta - 0.14 * sin(theta) - 0.42 * sin(2 * theta)
            var pitch: Float = 0
            var roll: Float = 0
            if settings.floats {
                let k = Float(q)
                yaw += 0.06 * sin(time * 0.6 + k * 1.7)
                pitch += 0.028 * sin(time * 0.8 + k * 0.9)
                roll += 0.014 * sin(time * 0.5 + k * 2.3)
                y += 0.024 * sin(time * 1.05 + k * 1.3)
            }
            yaw += tilt.x * 0.32 * settings.tilt * near * (1 - away)
            pitch += tilt.y * 0.2 * settings.tilt * near * (1 - away)
            yaw += p.spinYaw
            pitch += p.spinPitch
            p.pop = min(1, p.pop + dt * 1.6)
            packs[q] = p
            let scale = 0.35 + 0.65 * StageEase.backOut(p.pop)
            let model = StageMath.model(position: [x, y, z], euler: [pitch, yaw, roll], scale: scale)
            let opened = opening.phase != .idle && q == opening.pack
            let gone = away > 0.97 && !opened
            let footprint = (abs(cos(yaw)) * PouchMetrics.width + abs(sin(yaw)) * 0.2 + 0.25) * scale
            let shadowModel = StageMath.translation([x, PouchMetrics.floorY + 0.002, z + 0.02])
                * StageMath.rotationX(-.pi / 2)
                * StageMath.scale([footprint * 1.15, 0.5 * scale, 1])
            let shadowOpacity = (night ? 0.7 : 0.42) * (1 - StageMath.clamp01(y * 4)) * scale * settings.shadow
            out.append(PackPose(model: model, position: [x, y, z], euler: [pitch, yaw, roll], scale: scale, visible: !gone && !opened, shadowModel: shadowModel, shadowOpacity: shadowOpacity))
        }
        poses = out
    }

    // MARK: - Camera and hit testing

    func layoutCamera() {
        let aspect = viewport.x / viewport.y
        let halfTan = tan(settings.fov * .pi / 180 / 2)
        let w = PouchMetrics.width, h = PouchMetrics.height
        let distance = max(h / 0.6 / (2 * halfTan), w / (aspect < 1 ? 0.6 : 0.5) / (2 * halfTan * aspect))
        radius = min(2.8, max(1.1, distance * halfTan * aspect * (aspect < 1 ? 1.4 : 1.05))) * settings.spacing
        var cam = StageCamera()
        cam.fovY = settings.fov * .pi / 180
        cam.aspect = aspect
        cam.position = [0, 0.26, distance]
        // On a tall screen the ring sits a little lower, leaving the top free.
        cam.target = [0, aspect < 1 ? 0.05 : -0.2, -0.4]
        cam.view = StageMath.lookAt(eye: cam.position, target: cam.target)
        cam.projection = StageMath.perspective(fovY: cam.fovY, aspect: aspect, near: 0.1, far: 60)
        camera = cam
    }

    private func rebuildPacks(popping: Bool) {
        let n = settings.packs
        packs = (0..<n).map { Pack(index: $0, pop: popping ? -Float($0) * 0.11 : 1) }
        if poses.count != n {
            let wrapped = StageMath.wrap(target.rounded(), Float(n))
            angle = wrapped
            target = wrapped
            velocity = 0
        }
        placePacks(0)
    }
}
