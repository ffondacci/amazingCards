import CoreGraphics
import Foundation
import simd

/// The opening of the front pack: it flies in front of the camera, waits
/// for the swipe, comes apart in the chosen style, drops away while the
/// cards rise out, then deals them one tap at a time.
extension StageScene {
    struct Anchor {
        var position: SIMD3<Float>
        var rotation: simd_quatf
        var distance: Float
        var halfWidth: Float
    }

    nonisolated static let tearLine = PouchMetrics.tearLine
    nonisolated static let lineY = (tearLine - 0.5) * PouchMetrics.height
    nonisolated static let stripMid = (tearLine - 0.5) * PouchMetrics.height + ((1 - tearLine) * PouchMetrics.height) / 2

    /// Timing of each style: when the cards are presented, when the rays
    /// come, and the three peek angles (cutting, just open, until).
    struct StyleTiming {
        var label: String
        var present: Float
        var reveal: Float
        var peek: (Float, Float, Float)
    }

    nonisolated static func timing(_ style: OpeningStyle) -> StyleTiming {
        switch style {
        case .tear: StyleTiming(label: "Tear here", present: 2.1, reveal: 1.35, peek: (0.14, 0.5, 0.85))
        case .rip: StyleTiming(label: "Rip it apart", present: 2.1, reveal: 1.3, peek: (0.14, 0.5, 0.85))
        case .zip: StyleTiming(label: "Pull the tab", present: 2.85, reveal: 1.9, peek: (0.25, 0.48, 0.7))
        case .melt: StyleTiming(label: "Melt here", present: 2.75, reveal: 1, peek: (0.2, 0.48, 1))
        case .roll: StyleTiming(label: "Roll it open", present: 2.95, reveal: 1.3, peek: (0.14, 0.5, 0.85))
        case .lid: StyleTiming(label: "Tear here", present: 2.05, reveal: 1, peek: (0.14, 0.5, 1.25))
        }
    }

    // MARK: - Camera frame

    /// Orientation of the camera, which the opened pack faces.
    var cameraRotation: simd_quatf {
        let v = camera.view
        let r = float3x3(SIMD3(v.columns.0.x, v.columns.0.y, v.columns.0.z),
                         SIMD3(v.columns.1.x, v.columns.1.y, v.columns.1.z),
                         SIMD3(v.columns.2.x, v.columns.2.y, v.columns.2.z))
        return simd_quatf(r.transpose)
    }

    /// Where an opened pack stands: in front of the camera, filling most of the view.
    func anchorBase() -> Anchor {
        let aspect = viewport.x / viewport.y
        let halfTan = tan(camera.fovY / 2)
        let distance = max(PouchMetrics.height / 0.84 / (2 * halfTan), PouchMetrics.width / 0.8 / (2 * halfTan * aspect))
        let forward = normalize(camera.target - camera.position)
        return Anchor(position: camera.position + forward * distance, rotation: cameraRotation, distance: distance, halfWidth: halfTan * aspect)
    }

    var halfTan: Float { tan(camera.fovY / 2) }

    // MARK: - Start, advance, leave

    /// Opens the pack at `index` with the cards `onOpen` hands back.
    public func open(_ index: Int) {
        guard opening.phase == .idle, index < poses.count, let cards = onOpen?(index), !cards.isEmpty else { return }
        dealtCards = cards
        let pose = poses[index]
        var o = OpeningState()
        o.openings = opening.openings + 1
        o.pack = index
        o.phase = .zoom
        o.style = settings.opening
        o.rare = settings.rareLast && cards.count > 1
        o.from = pose.position
        o.fromRotation = Self.quaternion(euler: pose.euler)
        o.fromScale = pose.scale
        o.position = o.from
        o.rotation = o.fromRotation
        o.scale = o.fromScale
        o.low = 1
        opening = o
        packs[index].spinYaw = 0
        packs[index].spinTarget = 0
        packs[index].spinVelocity = 0
        packs[index].spinPitch = 0
        packs[index].spinPitchVelocity = 0
        hint = nil
        openingPose = OpeningPose()
        openingPose.visible = true
        openingPose.bodyVisible = true
    }

    /// Puts everything away, whatever the phase.
    public func exit() {
        guard opening.phase != .idle, opening.phase != .exit else { return }
        opening.exitFrom = opening.phase
        opening.exitAt = opening.tau
        opening.exitT0 = opening.t
        opening.unopened = opening.phase == .zoom || opening.phase == .ready || opening.phase == .cut
        opening.exitPosition = opening.position
        opening.exitRotation = opening.rotation
        opening.exitScale = opening.scale
        opening.phase = .exit
        hint = nil
    }

    /// A tap, or a short swipe, while the pack is open: starts the cut,
    /// deals the next card, or puts the fan away.
    func advanceOpening(direction: Float) {
        switch opening.phase {
        case .ready, .cut:
            opening.phase = .cut
            opening.manual = false
        case .present:
            dealNext(direction: direction)
        case .fan:
            if opening.tau > opening.fanAt + 0.6 { exit() }
        default:
            break
        }
    }

    /// The finger tearing the strip.
    func cutByHand(dx: Float) {
        guard opening.phase == .ready || opening.phase == .cut else { return }
        let span = viewport.y * 0.84 * (PouchMetrics.width / PouchMetrics.height)
        opening.phase = .cut
        opening.manual = true
        opening.cut = StageMath.clamp01(opening.cut + abs(dx) / (span * (opening.style == .rip ? 0.5 : 1)))
    }

    private func dealNext(direction: Float) {
        guard opening.phase == .present else { return }
        let count = min(5, dealtCards.count)
        if opening.top == count - 1 {
            if opening.rare {
                if opening.revealAt == 0 {
                    if opening.tau >= opening.premAt { reveal() }
                    return
                }
                if opening.tau < opening.revealAt + 1.1 { return }
            }
            opening.phase = .fan
            opening.fanAt = opening.tau
            show("Tap to put them away")
            return
        }
        opening.cards[opening.top].dealtAt = opening.tau
        opening.cards[opening.top].direction = direction
        opening.top += 1
        if opening.top == count - 1 {
            if opening.rare {
                opening.premAt = opening.tau + 0.3
                show("Something rare is inside · tap to reveal")
            } else {
                show("\(count) / \(count) · tap to see them all")
            }
        } else {
            show("\(opening.top + 1) / \(count) · tap for the next card")
        }
    }

    func reveal() {
        guard opening.revealAt == 0 else { return }
        opening.revealAt = opening.tau
        opening.burst = false
        show("★ tap to see all five")
    }

    private func finish(reappear: Bool) {
        let index = opening.pack
        opening.phase = .idle
        openingPose = OpeningPose()
        if index < packs.count { packs[index].pop = reappear ? 1 : 0 }
        dealtCards = []
        show("Drag the pack to turn it · tap to open")
    }

    private func show(_ text: String?) {
        hint = settings.hints ? text : nil
    }

    nonisolated static func quaternion(euler e: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: e.y, axis: [0, 1, 0]) * simd_quatf(angle: e.x, axis: [1, 0, 0]) * simd_quatf(angle: e.z, axis: [0, 0, 1])
    }

    // MARK: - Frame

    func stepOpening(_ rawDt: Float) {
        guard opening.phase != .idle else { return }
        let dt = rawDt * min(4, max(0.1, settings.speed))
        opening.t += dt
        let anchor = anchorBase()
        let style = opening.style
        let timing = Self.timing(style)
        var o = opening

        // Held low while being torn, rising as the cards come.
        let lowWanted: Float = (o.phase == .zoom || o.phase == .ready || o.phase == .cut
                                || (o.phase == .open && openingPose.bodyVisible && bodyPosition.y > -0.1)) ? 1 : 0
        o.low += (lowWanted - o.low) * (1 - exp(-dt * 4))
        var target = anchor.position
        let up = anchor.rotation.act(SIMD3<Float>(0, 1, 0))
        target += up * (-min(0.5, max(0, settings.hold)) * 2 * anchor.distance * halfTan * o.low)

        // Peek: tilt toward the viewer while cutting and just after.
        let peekWanted: Float = o.phase == .cut ? timing.peek.0 : (o.phase == .open && o.tau < timing.peek.2 ? timing.peek.1 : 0)
        o.peek += (peekWanted - o.peek) * (1 - exp(-dt * 6))
        let tiltRotation = Self.quaternion(euler: [tilt.y * 0.14 * settings.tilt + o.peek, tilt.x * 0.22 * settings.tilt, 0])
        let facing = anchor.rotation * tiltRotation

        // Guide line on the strip.
        let guideWanted: Float = o.phase == .ready ? 1 : (o.phase == .cut ? 0.35 : 0)
        o.guide += (guideWanted - o.guide) * (1 - exp(-dt * 8))

        if o.phase == .zoom {
            let k = StageEase.smooth(StageMath.clamp01(o.t / 0.85))
            o.position = mix(o.from, target, t: k)
            o.rotation = simd_slerp(o.fromRotation, facing, k) * simd_quatf(angle: sin(k * .pi) * 0.35, axis: [0, 1, 0])
            o.scale = StageMath.lerp(o.scale, 1, k)
            if o.t >= 0.85 {
                o.phase = .ready
                o.t = 0
                sweepStart = time
                show(style.hint)
            }
            opening = o
            composePieces(reset: true)
            return
        }

        if o.phase == .exit, o.unopened {
            let k = StageMath.progress(o.t, o.exitT0, o.exitT0 + 0.75)
            if o.cut > 0 {
                let e = StageEase.inCubic(k)
                o.position = o.exitPosition - SIMD3(0, 3.4 * e, 0)
                o.rotation = o.exitRotation * simd_quatf(angle: 0.35 * e, axis: [1, 0, 0]) * simd_quatf(angle: 0.12 * e, axis: [0, 0, 1])
            } else {
                let pose = poses[o.pack]
                let e = StageEase.smooth(k)
                o.position = mix(o.exitPosition, pose.position, t: e)
                o.rotation = simd_slerp(o.exitRotation, Self.quaternion(euler: pose.euler), e) * simd_quatf(angle: -sin(e * .pi) * 0.3, axis: [0, 1, 0])
                o.scale = StageMath.lerp(o.exitScale, pose.scale, e)
            }
            opening = o
            composePieces(reset: false)
            if k >= 1 { finish(reappear: o.cut == 0) }
            return
        }

        if o.phase != .exit {
            o.position = target
            o.rotation = simd_slerp(o.rotation, facing, 1 - exp(-dt * 10))
            o.scale = 1
        }

        if o.phase == .ready || o.phase == .cut {
            if o.phase == .ready, settings.autoOpen > 0, o.t > settings.autoOpen { o.phase = .cut }
            if o.phase == .cut, hint != nil { show(nil) }
            let cutting = o.phase == .cut
            let automatic = cutting && !o.manual
            let before = o.cut
            let jerky: (Float) -> Float = { d in (dt / d) * (0.35 + 1.3 * max(0, sin(o.t * 21) + 0.55 * sin(o.t * 47 + 1))) }
            var flakeScale: Float = 1
            var smoke: Float = 0
            switch style {
            case .tear, .lid, .rip:
                if automatic { o.cut = min(1, o.cut + jerky(style == .rip ? 0.6 : 0.75)) }
                let delta = o.cut - before
                o.jolt = min(1, o.jolt * exp(-dt * 18) + delta * 6)
                o.position.y += 0.004 * o.jolt
                o.flakeAcc += delta * 26
            case .roll:
                if automatic { o.cut = min(1, o.cut + (dt / 1.15) * (0.6 + 0.6 * max(0, sin(o.t * 13)))) }
                let delta = o.cut - before
                o.flakeAcc += delta * 16
                if delta > 0 { o.position.y += 0.0012 * sin(o.t * 60) }
            case .zip:
                if automatic { o.cut = min(1, o.cut + dt / 1.05) }
                let delta = o.cut - before
                o.flakeAcc += delta * 40
                flakeScale = 0.8
                if delta > 0 { o.position.y += 0.0015 * sin(o.t * 95) }
            case .melt:
                if automatic { o.cut = min(1, o.cut + dt / 1.15) }
                let delta = o.cut - before
                o.flakeAcc += delta * 9
                flakeScale = 0.7
                if delta > 0 { smoke = dt * 22 }
            }
            opening = o
            composePieces(reset: false)
            shedFlakes(scale: flakeScale)
            if smoke > 0 {
                opening.smokeAcc += smoke * max(0, settings.particles)
                while opening.smokeAcc > 1 {
                    opening.smokeAcc -= 1
                    particles.puff(at: cutTips()[0] + SIMD3(0, 0.02, 0.03))
                }
                if Float.random(in: 0..<1) < 0.5 { particles.spawnSparks(at: cutTips()[0], count: 1, spread: [0.01, 0.01, 0.01], speed: 1.2, lift: 0.5) }
            }
            if o.cut >= 1 {
                opening.phase = .open
                opening.tau = 0
                opening.cut = 1
                let n = style == .melt ? 0 : (style == .rip ? 14 : 12)
                for k in 0..<n {
                    let tips = cutTips(0.55 + Float.random(in: 0..<1) * 0.45)
                    for _ in 0..<particles.count(1, dial: settings.particles) { particles.flake(at: tips[k % tips.count]) }
                }
            }
            return
        }

        o.tau += dt
        let tau = o.tau
        if o.phase == .open, tau > timing.present {
            o.phase = .present
            let count = min(5, dealtCards.count)
            show("1 / \(count) · tap for the next card")
        }
        // Rare card: the aura ramps up while it waits face down, bursts when revealed.
        let premium = o.rare && o.premAt > 0 && tau >= o.premAt && o.phase != .exit
        if o.rare, o.phase == .present, o.premAt > 0, o.revealAt == 0, tau > o.premAt + 5 {
            opening = o
            reveal()
            o = opening
        }
        let auraWanted: Float = premium ? (o.phase == .fan ? 0.45 : (o.revealAt > 0 ? 1 : 0.7)) : 0
        o.aura += (auraWanted - o.aura) * (1 - exp(-dt * 4))
        opening = o
        composePieces(reset: false)
        o = opening
        if style == .melt, o.phase == .open {
            if tau < 0.7 {
                o.smokeAcc += dt * 10 * max(0, settings.particles)
                while o.smokeAcc > 1 {
                    o.smokeAcc -= 1
                    particles.puff(at: cutTips(Float.random(in: 0..<1))[0] + SIMD3(0, 0.02, 0.03))
                }
            }
            if openingPose.stripVisible, openingPose.strip.dissolve > 0, Float.random(in: 0..<1) < 0.8 {
                let local = SIMD4<Float>((Float.random(in: 0..<1) - 0.5) * PouchMetrics.width, Self.stripMid + (Float.random(in: 0..<1) - 0.5) * (1 - Self.tearLine) * PouchMetrics.height, 0.02, 1)
                let w = openingPose.stripModel * local
                particles.spawnSparks(at: SIMD3(w.x, w.y, w.z), count: 2, spread: .zero, speed: 1.6, lift: 0.35)
            }
        }
        if premium, Float.random(in: 0..<1) < 0.7, let last = openingPose.cards.indices.last {
            let p = cardWorld(last, offset: [(Float.random(in: 0..<1) - 0.5) * Self.cardWidth * 1.2, -cardHeight * 0.45, 0.02])
            particles.spawnSparks(at: p, count: particles.count(1, dial: settings.particles), spread: [0.02, 0.02, 0.02], speed: 2.2, lift: 0.35, gold: true)
        }
        if o.rare, o.revealAt > 0, !o.burst, tau >= o.revealAt + 0.42, let last = openingPose.cards.indices.last {
            o.burst = true
            sweepStart = time
            burstTime = Date.timeIntervalSinceReferenceDate
            let centre = cardWorld(last)
            particles.spawnSparks(at: centre, count: particles.count(160, dial: settings.particles), spread: [0.3, 0.4, 0.05], speed: 2.6, lift: 0.5, gold: true)
            for k in 0..<particles.count(90, dial: settings.particles) {
                particles.spawnFlake(
                    at: centre + SIMD3((Float.random(in: 0..<1) - 0.5) * 0.3, (Float.random(in: 0..<1) - 0.5) * 0.4, 0.05),
                    velocity: SIMD3((Float.random(in: 0..<1) - 0.5) * 3, 0.8 + Float.random(in: 0..<1) * 2.2, 0.3 + Float.random(in: 0..<1) * 1.2),
                    size: 0.015 + Float.random(in: 0..<1) * 0.03,
                    color: StageParticles.burstFlakes[k % 4],
                    life: 1.6 + Float.random(in: 0..<1)
                )
            }
        }
        if o.phase == .exit {
            let k = StageEase.inCubic(StageMath.progress(tau, o.exitAt, o.exitAt + 0.5))
            exitDrop = 3.2 * k
            if tau > o.exitAt + 0.78 {
                opening = o
                finish(reappear: false)
                return
            }
        }
        opening = o
        composePieces(reset: false)
    }
}
