import CoreGraphics
import Foundation
import simd

/// Where the body and the strip of the opened pack are, what their shaders
/// are told, and where the foil is being cut.
extension StageScene {
    /// World position on the tear line at `x` (0…1 along the cut), a little in front of the body.
    func cutPoint(_ x: Float, lift: Float = 0.03) -> SIMD3<Float> {
        let local = SIMD4<Float>((x - 0.5) * PouchMetrics.width * 0.95, Self.lineY, lift, 1)
        let world = openingPose.bodyModel * local
        return SIMD3(world.x, world.y, world.z)
    }

    /// Where the foil is being cut right now, for every cutting point of the style.
    func cutTips(_ cut: Float? = nil) -> [SIMD3<Float>] {
        let c = cut ?? opening.cut
        switch opening.style {
        case .zip: return [cutPoint(1 - c)]
        case .rip: return [cutPoint(0.5 - c / 2), cutPoint(0.5 + c / 2)]
        default: return [cutPoint(c)]
        }
    }

    /// Spawns the flakes accumulated by the cut.
    func shedFlakes(scale: Float = 1) {
        let tips = cutTips()
        var i = 0
        while opening.flakeAcc > 1 {
            opening.flakeAcc -= 1
            let n = particles.count(1, dial: settings.particles)
            for _ in 0..<n { particles.flake(at: tips[i % tips.count], scale: scale) }
            i += 1
        }
    }

    /// Position of a card's centre in the world.
    func cardWorld(_ index: Int, offset: SIMD3<Float> = .zero) -> SIMD3<Float> {
        guard index < openingPose.cards.count else { return opening.position }
        let w = openingPose.cards[index].model * SIMD4(offset, 1)
        return SIMD3(w.x, w.y, w.z)
    }

    // MARK: - Pieces

    var bodyPosition: SIMD3<Float> { pieceMotion.bodyPosition }

    /// Where the body and the strip are, relative to the anchor, for the
    /// current style and time. Also the dials of both.
    struct PieceMotion {
        var bodyPosition = SIMD3<Float>.zero
        var bodyRotation = SIMD3<Float>.zero
        var bodyVisible = true
        var stripPosition = SIMD3<Float>(0, StageScene.stripMid, 0)
        var stripRotation = SIMD3<Float>.zero
        var stripVisible = true
        var mouth: Float = 0
        var dissolve: Float = 0
        var fly: Float = 0
        var heat: Float = 0
        var tipGlow: Float = 0
        var innerGlow: Float = 0
    }

    var pieceMotion: PieceMotion {
        var m = PieceMotion()
        let o = opening
        let style = o.style
        guard o.phase == .open || o.phase == .present || o.phase == .fan || (o.phase == .exit && !o.unopened) else {
            m.heat = style == .melt && o.phase == .cut ? 1 : 0
            m.tipGlow = style == .melt && o.phase == .cut && o.cut > 0 ? 1 : 0
            return m
        }
        let tau = o.tau
        let p = StageMath.progress
        switch style {
        case .tear:
            let s = p(tau, 0, 0.9)
            m.stripPosition = [3 * s * s, Self.stripMid + 0.5 * StageEase.outCubic(s) - 2.6 * s * s * s, 0.3 * s]
            m.stripRotation = [-0.6 * s, 0.5 * s, -1.2 * s * s]
            m.stripVisible = s < 1
            m.mouth = StageEase.outCubic(p(tau, 0, 0.35))
            let d = StageEase.inCubic(p(tau, 1, 1.6))
            m.bodyPosition = [0, -0.025 * sin(.pi * p(tau, 0, 0.3)) - 3.2 * d, -0.2 * d]
            m.bodyRotation = [0.25 * d, 0, 0.06 * d]
            m.bodyVisible = d < 1
        case .rip:
            m.fly = p(tau, 0, 0.9)
            m.stripVisible = m.fly < 1
            m.mouth = StageEase.outCubic(p(tau, 0, 0.35))
            let d = StageEase.inCubic(p(tau, 0.95, 1.55))
            m.bodyPosition = [0, -0.03 * sin(.pi * p(tau, 0, 0.3)) - 3.2 * d, -0.2 * d]
            m.bodyRotation = [0.25 * d, 0, -0.05 * d]
            m.bodyVisible = d < 1
        case .zip:
            let s = p(tau, 0.12, 0.95)
            m.stripPosition = [0, Self.stripMid - 2.9 * s * s, -0.3 * StageEase.outCubic(s)]
            m.stripRotation = [-0.7 * s, 0, 0.15 * s]
            m.stripVisible = s < 1
            m.mouth = StageEase.outCubic(p(tau, 0.1, 0.45))
            let tilt = StageEase.smooth(p(tau, 0.45, 0.95))
            let d = StageEase.inCubic(p(tau, 1.95, 2.45))
            m.bodyRotation = [0, 0, -1.95 * tilt - 0.4 * d]
            m.bodyPosition = [-0.5 * tilt - 0.4 * d, 0.12 * tilt - 3.2 * d, -0.2 * d]
            m.bodyVisible = d < 1
        case .melt:
            m.stripPosition = [0.04 * sin(tau * 1.4), Self.stripMid + 0.13 * StageEase.outCubic(p(tau, 0, 1.2)), 0.08 * tau]
            m.stripRotation = [0.1 * sin(tau * 1.1), 0, 0.07 * sin(tau * 1.7)]
            m.dissolve = p(tau, 0.1, 1.1)
            m.stripVisible = m.dissolve < 1
            m.heat = 1 - p(tau, 0, 1.3)
            m.mouth = StageEase.outCubic(p(tau, 0, 0.45))
            let d = StageEase.inCubic(p(tau, 1, 1.75))
            m.bodyPosition = [0, -3.2 * d, -0.2 * d]
            m.bodyRotation = [0.2 * d, 0, 0]
            m.bodyVisible = d < 1
        case .roll:
            let s = p(tau, 0.08, 0.9)
            m.stripPosition = [0.12 * s + 1.5 * s * s, Self.stripMid + 0.35 * StageEase.outCubic(s) - 2.5 * s * s * s, 0.25 * s]
            m.stripRotation = [0.4 * s, 0, -1.3 * s * s]
            m.stripVisible = s < 1
            m.mouth = StageEase.outCubic(p(tau, 0, 0.35))
            let d = StageEase.inCubic(p(tau, 0.95, 1.45))
            m.bodyPosition = [0, -3.2 * d, -0.2 * d]
            m.bodyRotation = [0.25 * d, 0, 0.05 * d]
            m.bodyVisible = d < 1
        case .lid:
            let drop = -0.55 * StageEase.smooth(p(tau, 0.15, 0.6))
            let d = StageEase.inCubic(p(tau, 1.55, 2.05))
            m.bodyPosition = [0, drop - 3.2 * d, -0.2 * d]
            m.bodyRotation = [0.25 * d, 0, 0]
            m.bodyVisible = d < 1
            let away = p(tau, 0.6, 1.25)
            let angle = -(2.1 * StageEase.outCubic(p(tau, 0, 0.5)) + 0.9 * away)
            let hinge = Self.lineY + drop
            let arm = Self.stripMid - Self.lineY
            m.stripPosition = [0, hinge + arm * cos(angle) - 0.03 * sin(angle) - 2.6 * away * away, -0.03 + arm * sin(angle) + 0.03 * cos(angle) - 0.35 * away]
            m.stripRotation = [angle, 0, 0]
            m.stripVisible = away < 1
            m.mouth = StageEase.outCubic(p(tau, 0, 0.4))
            m.innerGlow = 0.22 * StageEase.outCubic(p(tau, 0, 0.3)) * (1 - p(tau, 0.8, 1.6))
        }
        if o.phase == .exit {
            m.bodyPosition.y -= exitDrop
        }
        return m
    }

    /// Assembles the pose of every piece and card for the renderer.
    func composePieces(reset: Bool) {
        let o = opening
        let motion = pieceMotion
        let style = o.style
        var pose = OpeningPose()
        pose.visible = true
        let anchor = StageMath.translation(o.position) * float4x4(o.rotation) * StageMath.scale(SIMD3(repeating: o.scale))

        var body = PieceDials()
        body.tearV = Self.tearLine
        body.cutP = o.cut
        body.inside = 1
        body.lineMode = style == .melt ? 2 : (style == .zip ? 3 : 0)
        body.cutDir = style == .zip ? 1 : (style == .rip ? 2 : 0)
        body.perf = style == .zip ? 1 : 0
        body.heat = motion.heat
        body.tipGlow = motion.tipGlow
        body.innerGlow = motion.innerGlow
        body.guide = o.guide
        body.mouth = motion.mouth
        body.mouthK = 1
        var strip = body
        strip.tearSide = 1
        strip.peel = style == .roll ? 2 : (style == .rip ? 3 : 1)
        strip.peelDir = style == .zip ? -1 : 1
        strip.peelAmt = style == .melt ? 0.5 : (style == .lid ? 0.35 : 1)
        strip.dissolve = motion.dissolve
        strip.fly = motion.fly
        strip.guide = 0
        strip.innerGlow = 0

        pose.body = body
        pose.strip = strip
        pose.bodyVisible = motion.bodyVisible
        pose.bodyModel = anchor * StageMath.translation(motion.bodyPosition) * StageMath.rotationYXZ(x: motion.bodyRotation.x, y: motion.bodyRotation.y, z: motion.bodyRotation.z)
        pose.stripVisible = motion.stripVisible && o.phase != .zoom
        pose.stripModel = anchor * StageMath.translation(motion.stripPosition)
            * StageMath.rotationYXZ(x: motion.stripRotation.x, y: motion.stripRotation.y, z: motion.stripRotation.z)
            * StageMath.translation([0, -Self.stripMid, 0])
        // Before the cut the strip is part of the body: one pass draws both sides of the line.
        if o.phase == .zoom || o.phase == .ready || (o.phase == .cut && o.cut <= 0.001) {
            pose.stripVisible = false
            pose.body.tearSide = 0
            pose.body.tearV = o.phase == .zoom ? 2 : Self.tearLine
            if o.phase != .zoom { pose.strip = strip; pose.stripVisible = true }
        }

        pose.cards = cardDraws(anchor: anchor, showInside: o.phase == .cut || o.phase == .open || o.phase == .present || o.phase == .fan || o.phase == .exit)
        pose.auraOpacity = o.aura
        pose.auraPulse = o.revealAt > 0 ? exp(-pow(o.tau - o.revealAt - 0.45, 2) / 0.04) : 0
        let dealing = o.phase == .open || o.phase == .present || o.phase == .fan
        pose.premium = o.rare && o.premAt > 0 && o.tau >= o.premAt && o.phase != .exit
        pose.raysOpacity = settings.rays && dealing && o.tau > Self.timing(style).reveal ? 1 : 0
        pose.dimOpacity = pose.premium ? 1 : 0
        openingPose = pose
    }
}
