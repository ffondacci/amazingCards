import CoreGraphics
import Foundation
import simd

/// Where the five cards of an opened pack are, frame by frame: resting
/// inside, rising out, presented one by one, flung aside, fanned out and
/// put away. All poses are in the opened pack's frame.
extension StageScene {
    nonisolated static let cardWidth: Float = 0.8

    /// Height of the cards, from the pictures handed in.
    var cardHeight: Float {
        guard let first = dealtCards.first, first.front.height > 0 else { return Self.cardWidth / 0.716 }
        return Self.cardWidth * Float(first.front.height) / Float(first.front.width)
    }

    /// Stacked inside the sealed pack.
    private func restPose(_ i: Int) -> CardPose {
        CardPose(x: 0, y: -0.1, z: Float(2 - i) * 0.0012, s: 1)
    }

    /// The tear choreography: rise out of the mouth, then come to the front.
    private func tearPose(_ i: Int, _ tau: Float) -> CardPose {
        let behind = Float(i - opening.top)
        let rise = StageEase.outCubic(StageMath.progress(tau, 0.25, 1))
        let settle = StageEase.smooth(StageMath.progress(tau, 1.45, 2.1))
        let y = StageMath.lerp(StageMath.lerp(-0.1, 0.5, rise), 0, settle) - max(0, behind) * 0.012 * settle
        let z = Float(2 - i) * 0.0012 * (1 - settle) + settle * (0.34 - max(0, behind) * 0.006)
        let s = StageMath.lerp(1, 1.3, settle)
        let rz = settle * (behind > 0 ? (Float((i * 7919) % 11) / 11 - 0.5) * 0.05 : 0)
        return CardPose(x: 0, y: y, z: z, rx: 0, ry: 0, rz: rz, s: s)
    }

    /// The other styles: each pours the cards out its own way, then hands over to `tearPose`.
    private func stylePose(_ i: Int, _ tau: Float) -> CardPose {
        let rest = restPose(i)
        let front = tearPose(i, 99)
        let p = StageMath.progress
        let out = CardPose(x: 0, y: 0.5, z: Float(2 - i) * 0.0012, s: 1)
        switch opening.style {
        case .rip:
            let k = p(tau, 0.2, 1)
            var bounce = rest
            bounce.y = k > 0 ? 0.5 - 0.6 * exp(-4 * k) * cos(9 * k) : rest.y
            return CardPose.mix(bounce, front, StageEase.smooth(p(tau, 1.5, 2.05)))
        case .zip:
            let tilt = StageEase.smooth(p(tau, 0.45, 0.95))
            let angle = -1.95 * tilt, ox = -0.5 * tilt, oy = 0.12 * tilt
            let start = 0.9 + Float(4 - i) * 0.16
            let slide = p(tau, start, start + 0.34)
            let along = StageMath.lerp(-0.1, 1.4, slide * slide)
            let slid = CardPose(x: ox - along * sin(angle), y: oy + along * cos(angle), z: Float(2 - i) * 0.0012, rz: angle, s: 1)
            let gather = p(tau, start + 0.3, start + 0.72)
            let portrait = viewport.x < viewport.y
            let pile = CardPose(x: (portrait ? 0.03 : 0.2) + 0.03 * Float(2 - i), y: -0.12, z: 0.32 + Float(4 - i) * 0.008, rz: 0.05 * Float(2 - i), s: 1.05)
            var mixed = CardPose.mix(slid, pile, StageEase.outCubic(gather))
            mixed.z = StageMath.lerp(slid.z, pile.z, StageMath.smoothstep(0, 0.3, gather))
            mixed.y -= 0.12 * sin(.pi * gather)
            return CardPose.mix(mixed, front, StageEase.smooth(p(tau, 2.35, 2.8)))
        case .melt:
            var floating = CardPose.mix(rest, out, StageEase.smooth(p(tau, 0.3, 1.5)))
            let wave = sin(.pi * p(tau, 1.55, 2.45))
            let anchor = anchorBase()
            let room = min(1, max(0.5, (2 * (anchor.distance - 0.22) * anchor.halfWidth) / 1.9))
            floating.x += 0.13 * Float(i - 2) * wave * room
            floating.y += 0.06 * sin(tau * 2.1 + Float(i)) * wave
            floating.z += 0.05 * Float(4 - i) * wave
            floating.rz += 0.07 * Float(2 - i) * wave
            floating.ry = 0.28 * sin(tau * 1.6 + Float(i) * 1.3) * wave
            return CardPose.mix(floating, front, StageEase.smooth(p(tau, 2.2, 2.7)))
        case .roll:
            var rising = CardPose.mix(rest, out, StageEase.outCubic(p(tau, 0.3, 0.95)))
            let anchor = anchorBase()
            let room = min(1, max(0.5, (2 * (anchor.distance - 0.22) * anchor.halfWidth) / 1.9))
            let spread = Float(2 - i) * 0.19
            let arc = CardPose(x: sin(spread) * 1.05 * room, y: (-0.62 + cos(spread) * 1.05) * room, z: 0.22 + Float(4 - i) * 0.006, rz: -spread, s: room)
            rising = CardPose.mix(rising, arc, StageEase.smooth(p(tau, 1.35, 1.9)))
            return CardPose.mix(rising, front, StageEase.smooth(p(tau, 2.35, 2.9)))
        case .lid, .tear:
            let drop = -0.55 * StageEase.smooth(p(tau, 0.15, 0.6))
            let start = 0.62 + Float(4 - i) * 0.15
            var lifted = rest
            lifted.y = StageMath.lerp(rest.y + drop, 0.86, StageEase.outCubic(p(tau, start, start + 0.32)))
            let swing = p(tau, start + 0.3, start + 0.78)
            var pose = CardPose.mix(lifted, front, StageEase.smooth(swing))
            pose.z += 0.25 * sin(.pi * swing)
            pose.rx += 0.55 * sin(.pi * swing)
            return pose
        }
    }

    /// Fanned out side by side.
    private func fanPose(_ i: Int) -> CardPose {
        let aspect = viewport.x / viewport.y
        let anchor = anchorBase()
        let room = (anchor.distance - 0.34) * anchor.halfWidth
        let gap: Float = aspect < 1 ? 0.34 : 0.72
        let scale = min(0.82, ((aspect < 1 ? 1.62 : 1.84) * room) / ((4 * gap + 1) * Self.cardWidth))
        let k = Float(i - 2)
        return CardPose(x: k * Self.cardWidth * scale * gap, y: -0.05 - 0.03 * k * k * scale, z: 0.34 + Float(i) * 0.004, rz: -k * 0.08, s: scale)
    }

    /// The rare card waits face down, trembling, then turns over with a pop.
    private func rarePose(_ pose: CardPose, _ tau: Float) -> CardPose {
        var p = pose
        let prem = opening.premAt, reveal = opening.revealAt
        if reveal == 0 || tau < reveal {
            p.ry += .pi
            if prem > 0, tau >= prem {
                let since = tau - prem
                let w = StageEase.outCubic(StageMath.progress(since, 0, 0.45))
                let v = w * min(1, 0.35 + since * 0.3)
                p.z += 0.1 * w
                p.s *= 1 + 0.05 * w
                p.x += 0.007 * v * sin(since * 57)
                p.y += 0.005 * v * sin(since * 43 + 1)
                p.rz += 0.014 * v * sin(since * 31)
            }
            return p
        }
        let since = tau - reveal
        let turn = StageMath.progress(since, 0, 0.9)
        p.ry += .pi * (1 - StageEase.smooth(turn))
        p.z += 0.1 + 0.14 * sin(.pi * turn)
        p.s *= 1.05 + 0.1 * sin(.pi * turn)
        let settle = StageMath.smoothstep(0.8, 1.6, since)
        p.ry += settle * 0.22 * sin((since - 0.8) * 1.1)
        p.rx += settle * 0.07 * sin((since - 0.8) * 1.5)
        p.y += settle * 0.015 * sin(since * 1.7)
        return p
    }

    /// Pose of card `i` for a phase and time.
    private func cardPose(_ i: Int, phase: StagePhase, tau: Float) -> CardPose {
        let timing = Self.timing(opening.style)
        var pose = opening.style == .tear ? tearPose(i, tau) : (tau < timing.present ? stylePose(i, tau) : tearPose(i, 99))
        let last = min(5, dealtCards.count) - 1
        if i == last, opening.rare { pose = rarePose(pose, tau) }
        let card = opening.cards[i]
        let fanning = phase == .fan
        if card.dealtAt >= 0, card.dealtAt <= tau {
            let k = StageMath.progress(tau, card.dealtAt, card.dealtAt + 0.5)
            let dir = card.direction
            let flung = CardPose(
                x: pose.x + dir * 3.2 * StageEase.inCubic(k) + dir * 0.2 * k,
                y: pose.y + 0.35 * k,
                z: pose.z + 0.3 * StageEase.outCubic(k * 2),
                rx: 0, ry: dir * 0.8 * k, rz: -dir * 0.55 * k, s: pose.s
            )
            pose = flung
            if fanning {
                let w = StageEase.outCubic(StageMath.progress(tau, opening.fanAt + Float(i) * 0.06, opening.fanAt + Float(i) * 0.06 + 0.65))
                let parked = CardPose(x: dir * 3.4, y: pose.y, z: pose.z, rx: 0, ry: dir * 0.8, rz: -dir * 0.55, s: pose.s)
                pose = CardPose.mix(k < 1 ? flung : parked, fanPose(i), w)
            }
        } else if fanning {
            pose = CardPose.mix(pose, fanPose(i), StageEase.smooth(StageMath.progress(tau, opening.fanAt, opening.fanAt + 0.6)))
            if i == last {
                pose.ry += 0.12 * sin(tau * 1.3)
                pose.y += 0.03 * StageMath.progress(tau, opening.fanAt, opening.fanAt + 0.6)
            }
        }
        return pose
    }

    private func drawOrder(_ i: Int, phase: StagePhase, z: Float) -> Int {
        let base = phase == .fan ? 20 + i : (opening.cards[i].dealtAt >= 0 ? 40 + i : 30 - i)
        return 100 + base + Int(30 * min(1.3, max(-1.3, z)))
    }

    /// The cards this frame, in world space.
    func cardDraws(anchor: float4x4, showInside: Bool) -> [OpeningPose.CardDraw] {
        let o = opening
        let count = min(5, dealtCards.count)
        guard count > 0, showInside else { return [] }
        let exiting = o.phase == .exit
        let phase = exiting ? o.exitFrom : o.phase
        let tau = exiting ? o.exitAt : o.tau
        let night = settings.lighting == .night
        var glow: Float = night ? 0.32 : 0
        if o.style == .melt { glow += 0.3 * sin(.pi * StageMath.progress(tau, 0.3, 2.7)) }
        var draws: [OpeningPose.CardDraw] = []
        for i in 0..<count {
            let visible = o.style == .tear ? tau > 0.28 : true
            if !visible { continue }
            var pose: CardPose
            if o.phase == .cut || o.phase == .ready {
                pose = restPose(i)
            } else {
                pose = cardPose(i, phase: phase, tau: tau)
            }
            if exiting {
                let delay = Float(o.cards[i].dealtAt < 0 ? max(0, i - o.top) : i) * 0.05
                let k = StageMath.progress(o.tau, o.exitAt + delay, o.exitAt + delay + 0.6)
                let side: Float = i % 2 == 1 ? 1 : -1
                pose.y += 0.12 * sin(.pi * min(1, k * 2.2)) - 3.2 * StageEase.inCubic(k)
                pose.x += side * 0.25 * k
                pose.rz += side * 0.5 * StageEase.inCubic(k)
                pose.rx += 0.5 * StageEase.inCubic(k)
                pose.s *= 1 - 0.3 * k
            }
            draws.append(OpeningPose.CardDraw(model: anchor * pose.model, order: drawOrder(i, phase: phase, z: pose.z), emissive: glow, faceDown: false))
        }
        return draws
    }
}
