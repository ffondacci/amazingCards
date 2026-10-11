import CoreGraphics
import Foundation
import simd

/// Pointer, tilt, drags, taps and hit testing of the stage.
extension StageScene {
    // MARK: - Inputs

    public func resize(_ size: CGSize) {
        viewport = [Float(max(size.width, 1)), Float(max(size.height, 1))]
        layoutCamera()
    }

    /// Device tilt in −1…1, used when no pointer hovers the stage.
    public func setDeviceTilt(_ t: CGPoint) {
        deviceTilt = [Float(t.x), Float(t.y)]
    }

    /// Pointer hover position in view points, nil when it leaves.
    public func pointerMoved(to point: CGPoint?) {
        guard let point else { pointerActive = false; return }
        pointer = [Float(point.x) / viewport.x * 2 - 1, Float(point.y) / viewport.y * 2 - 1]
        pointerActive = true
    }

    public func dragBegan(at point: CGPoint, time now: TimeInterval) {
        var d = Drag(start: point, last: point, startTime: now, lastTime: now)
        hint = nil
        if opening.phase == .idle, let hit = pack(at: point), hit == frontIndex, abs(angle - target) < 0.3 {
            d.spinning = hit
            packs[hit].spinVelocity = 0
            packs[hit].spinPitchVelocity = 0
        }
        drag = d
    }

    public func dragChanged(to point: CGPoint, time now: TimeInterval) {
        guard var d = drag else { return }
        let dx = Float(point.x - d.last.x), dy = Float(point.y - d.last.y)
        let dt = max(0.001, Float(now - d.lastTime))
        d.last = point
        d.lastTime = now
        d.moved += abs(CGFloat(dx)) + abs(CGFloat(dy))
        drag = d
        if opening.phase != .idle {
            if opening.phase == .ready || opening.phase == .cut {
                cutByHand(dx: dx)
            }
            return
        }
        if let i = d.spinning {
            let step = dx * 0.011
            packs[i].spinYaw += step
            packs[i].spinPitch = min(0.7, max(-0.7, packs[i].spinPitch + dy * 0.007))
            d.speed = StageMath.lerp(d.speed, step / dt, 0.4)
        } else {
            let perPoint = 1 / max(260, viewport.x * 0.32)
            angle -= dx * perPoint
            d.speed = StageMath.lerp(d.speed, -dx * perPoint / dt, 0.4)
        }
        drag = d
    }

    public func dragEnded(at point: CGPoint, time now: TimeInterval) {
        guard let d = drag else { return }
        drag = nil
        let isTap = d.moved < 8 && now - d.startTime < 0.45
        let travel = Float(point.x - d.start.x)
        if opening.phase != .idle {
            if isTap || abs(travel) > 40 || opening.phase == .cut { advanceOpening(direction: travel < 0 ? -1 : 1) }
            return
        }
        if isTap {
            guard let hit = pack(at: point) else { return }
            if hit == frontIndex, abs(angle - target) < 0.3 {
                open(hit)
            } else {
                bringToFront(hit)
            }
        } else if let i = d.spinning {
            let v = min(30, max(-30, d.speed))
            packs[i].spinVelocity = v
            packs[i].spinTarget = ((packs[i].spinYaw + v * 0.12) / .pi).rounded() * .pi
        } else {
            velocity = d.speed
            target = (angle + min(2, max(-2, d.speed * 0.2))).rounded()
        }
    }

    /// Turns the carousel so `index` faces the camera, the short way round.
    public func bringToFront(_ index: Int) {
        let n = Float(packs.count)
        var delta = Float(index) - StageMath.wrap(target.rounded(), n)
        delta = StageMath.wrap(delta + n / 2, n) - n / 2
        target = target.rounded() + delta.rounded()
    }

    /// Ray through a view point, in world space.
    func ray(at point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let ndc = SIMD2<Float>(Float(point.x) / viewport.x * 2 - 1, 1 - Float(point.y) / viewport.y * 2)
        let inverse = camera.viewProjection.inverse
        let near = inverse * SIMD4<Float>(ndc.x, ndc.y, 0, 1)
        let far = inverse * SIMD4<Float>(ndc.x, ndc.y, 1, 1)
        let a = SIMD3(near.x, near.y, near.z) / near.w
        let b = SIMD3(far.x, far.y, far.z) / far.w
        return (a, normalize(b - a))
    }

    /// The nearest pack under a view point, if any.
    public func pack(at point: CGPoint) -> Int? {
        let (origin, direction) = ray(at: point)
        let half = SIMD3<Float>(PouchMetrics.width / 2, PouchMetrics.height / 2, 0.09)
        var best: (Int, Float)?
        for (i, pose) in poses.enumerated() where pose.visible {
            let inverse = pose.model.inverse
            let o4 = inverse * SIMD4(origin, 1)
            let d4 = inverse * SIMD4(direction, 0)
            let o = SIMD3(o4.x, o4.y, o4.z), d = SIMD3(d4.x, d4.y, d4.z)
            var tMin: Float = -.infinity, tMax: Float = .infinity
            var missed = false
            for axis in 0..<3 {
                if abs(d[axis]) < 1e-6 {
                    if abs(o[axis]) > half[axis] { missed = true; break }
                } else {
                    var t1 = (-half[axis] - o[axis]) / d[axis]
                    var t2 = (half[axis] - o[axis]) / d[axis]
                    if t1 > t2 { swap(&t1, &t2) }
                    tMin = max(tMin, t1)
                    tMax = min(tMax, t2)
                    if tMin > tMax { missed = true; break }
                }
            }
            if missed || tMax < 0 { continue }
            let t = max(tMin, 0)
            if best == nil || t < best!.1 { best = (i, t) }
        }
        return best?.0
    }
}
