import CardCore
import CoreGraphics
import Foundation
import QuartzCore

/// How a parallax card is shown.
public enum ParallaxMode: String, Hashable, Sendable, CaseIterable, Identifiable {
    /// The card, tilting under the finger.
    case card
    /// Its layers pulled apart in depth.
    case stack
    /// Its layers side by side.
    case spread

    public var id: String { rawValue }
}

/// Springs and placements of one parallax card, stepped once per frame
/// by the view. A plain class: the view reads it while drawing, the
/// gestures write it, nothing observes it.
@MainActor
final class ParallaxEngine {
    struct Placement {
        var transform: CATransform3D
        /// 2D parallax slide of the picture inside its slot.
        var slide: CGPoint
        /// Scale of a cover picture, so its edges never show.
        var coverScale: CGFloat
        /// 0…1 how far the layer has left the card (stack or spread).
        var open: CGFloat
        /// Opacity of the tile under the layer and of its outline, for the stack and spread views.
        var tileOpacity: CGFloat
        var edgeOpacity: CGFloat
    }

    private struct LayerState {
        var stack: Double = 0, stackV: Double = 0
        var spread: Double = 0, spreadV: Double = 0
    }

    // Angles in degrees.
    var rx: Double = 6, ry: Double = -170, rz: Double = 0
    private var vx: Double = 0, vy: Double = 0, vz: Double = 0
    var base: Double = 0
    var hx: Double = 0, hy: Double = 0, hover: Double = 0
    var dragging = false
    private var dragX: Double = 0, dragY: Double = 0
    private var moved: Double = 0
    private var lastTap: TimeInterval = 0
    private var lastPoint: CGPoint = .zero
    private var tilt = CGPoint.zero
    private(set) var mode: ParallaxMode = .card
    private var modeChangedAt: TimeInterval = 0
    private var settling = false
    private var spreadBlend: Double = 0
    private var layers: [LayerState] = []
    private var lastStep: TimeInterval?
    /// Time not yet simulated: the springs run at 60 steps per second
    /// whatever the display rate, so a 120 Hz screen does not double their speed.
    private var pending: TimeInterval = 0
    private(set) var time: TimeInterval = 0
    /// Lift and shrink of the card while its layers are out.
    private(set) var lift: Double = 0
    private(set) var cardScale: Double = 1
    /// 0…1 how open the card is overall.
    private(set) var openness: Double = 0

    var reduceMotion = false

    func reset(layerCount: Int) {
        if layers.count != layerCount { layers = Array(repeating: LayerState(), count: layerCount) }
    }

    // MARK: - Inputs

    /// Finger or pointer position relative to the card's centre, in card widths.
    func pointer(at point: CGPoint?, cardWidth: CGFloat, center: CGPoint) {
        guard let point else { if !dragging { hover = 0 }; return }
        hx = min(1, max(-1, Double((point.x - center.x) / (cardWidth * 0.75))))
        hy = min(1, max(-1, Double((point.y - center.y) / (cardWidth * 0.9))))
        hover = 1
    }

    /// Device tilt in −1…1, a gentle stand-in for the pointer when nothing touches the card.
    func deviceTilt(_ t: CGPoint) {
        tilt = t
        if !dragging {
            let strength = min(1, hypot(t.x, t.y) * 2)
            if strength > 0.02 {
                hx = Double(t.x)
                hy = Double(-t.y)
                hover = 0.55 * Double(strength)
            } else if hover < 0.56 {
                hover = 0
            }
        }
    }

    func dragBegan(at point: CGPoint, time now: TimeInterval) {
        dragging = true
        moved = 0
        lastPoint = point
    }

    func dragChanged(to point: CGPoint, cardWidth: CGFloat, center: CGPoint, time now: TimeInterval) {
        let dx = Double(point.x - lastPoint.x), dy = Double(point.y - lastPoint.y)
        moved += abs(dx) + abs(dy)
        if mode != .spread {
            dragY += dx * 0.45
            dragX = min(26, max(-26, dragX - dy * 0.25))
        }
        lastPoint = point
        pointer(at: point, cardWidth: cardWidth, center: center)
    }

    func dragEnded(time now: TimeInterval) {
        guard dragging else { return }
        dragging = false
        hover = 0
        if mode == .card {
            let total = base + dragY
            base = (total / 180).rounded() * 180
            dragY = total - base
            if moved < 8 {
                if now - lastTap < 0.34 {
                    flip(hx >= 0 ? 1 : -1)
                    lastTap = 0
                } else {
                    lastTap = now
                }
            }
        }
        deviceTilt(tilt)
    }

    /// Turns the card over.
    func flip(_ direction: Double = 1) {
        guard mode == .card else { return }
        base += 180 * direction
    }

    func show(_ view: ParallaxMode, time now: TimeInterval) {
        guard view != mode else { return }
        if view != .card { base = (base / 360).rounded() * 360 }
        settling = view == .card
        mode = view
        modeChangedAt = now
    }

    // MARK: - Frame

    /// Advances the springs to `now`. Returns the card's transform inputs.
    func step(now: TimeInterval, motion: ParallaxMotion, layerCount: Int) {
        reset(layerCount: layerCount)
        let dt = lastStep.map { min(0.05, max(0, now - $0)) } ?? 0
        lastStep = now
        time = now
        let t = now
        let tiltDeg = motion.tilt
        let sway = motion.sways && !reduceMotion
        let response = min(3, max(0.2, motion.response))
        let still = 1 - hover
        var targetY: Double, targetX: Double, targetZ: Double = 0
        switch mode {
        case .stack:
            targetY = base
            targetX = 56 - hy * 9 * hover + dragX * 0.6
            targetZ = -34 + hx * 14 * hover + (sway ? sin(t * 0.35) * 5 : 0) + dragY * 0.5
        case .spread:
            targetY = base + hx * 4 * hover
            targetX = -hy * 3 * hover
        case .card:
            targetY = base + hx * tiltDeg * hover + (sway ? sin(t * 0.55) * 9 * still : 0) + dragY
            targetX = -hy * tiltDeg * 0.73 * hover + (sway ? sin(t * 0.8 + 1) * 4 * still : 0) + dragX
        }
        if !dragging {
            dragY *= 0.9
            dragX *= 0.9
        }
        pending += dt
        let steps = Int(pending * 60)
        pending -= Double(steps) / 60
        let pull = 0.15 * response
        let damping = max(0.55, 0.7 - (response - 1) * 0.05)
        let easing = mode == .card && now - modeChangedAt < 1.6 && settling
        for _ in 0..<steps {
            if easing {
                vx = 0; vy = 0; vz = 0
                ry += (targetY - ry) * 0.1
                rx += (targetX - rx) * 0.1
                rz += (targetZ - rz) * 0.1
                continue
            }
            vy += (targetY - ry) * pull; vy *= damping; ry += vy
            vx += (targetX - rx) * pull; vx *= damping; rx += vx
            vz += (targetZ - rz) * 0.06; vz *= 0.84; rz += vz
        }
        // Layers leaving the card, one after the other.
        let since = now - modeChangedAt
        let n = layers.count
        for i in 0..<n {
            let order = mode == .card ? n - 1 - i : i
            let due = since > 0.12 + Double(order) * 0.075
            let wantStack: Double = mode == .stack && due ? 1 : 0
            let wantSpread: Double = mode == .spread && due ? 1 : 0
            var s = layers[i]
            for _ in 0..<steps {
                if wantStack > 0 {
                    s.stackV += (wantStack - s.stack) * 0.075; s.stackV *= 0.8; s.stack += s.stackV
                } else {
                    s.stackV = 0; s.stack += (0 - s.stack) * 0.12; if s.stack < 0.003 { s.stack = 0 }
                }
                if wantSpread > 0 {
                    s.spreadV += (wantSpread - s.spread) * 0.08; s.spreadV *= 0.79; s.spread += s.spreadV
                } else {
                    s.spreadV = 0; s.spread += (0 - s.spread) * 0.12; if s.spread < 0.003 { s.spread = 0 }
                }
            }
            layers[i] = s
        }
        spreadBlend += ((mode == .spread ? 1 : 0) - spreadBlend) * (1 - pow(0.8, Double(steps)))
        let maxStack = layers.map(\.stack).max() ?? 0
        openness = min(1, max(0, layers.map { max($0.stack, $0.spread) }.max() ?? 0))
        let q = min(1.2, max(0, maxStack))
        let fit = min(1, max(0.4, 64 / (40 + Double(max(1, n) - 1) * 8.6 * 0.83)))
        lift = (mode == .card && sway ? sin(t * 0.9) * 0.35 : 0) + q * 2
        cardScale = 1 - (1 - fit) * q
    }

    /// Angle of the card around its resting face, −180…180.
    var turn: Double {
        (((ry - base).truncatingRemainder(dividingBy: 360)) + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    /// Whether the front of the card faces the viewer.
    var showsFront: Bool {
        cos(ry * .pi / 180) * cos(rx * .pi / 180) >= 0
    }

    // MARK: - Placement

    /// Transform of the card itself in a view of `size`, with the layer-specific part appended by `layerTransform`.
    func cardTransform(size: CGSize, em: CGFloat, layer: ((inout CATransform3D) -> Void)? = nil, flipped: Bool = false) -> CATransform3D {
        let perspective = size.width * 3.2
        var persp = CATransform3DIdentity
        persp.m34 = -1 / perspective
        var m = CATransform3DConcat(persp, CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0))
        m = CATransform3DTranslate(m, 0, CGFloat(lift) * em, 0)
        m = CATransform3DScale(m, CGFloat(cardScale), CGFloat(cardScale), 1)
        m = CATransform3DRotate(m, CGFloat(rx * .pi / 180), 1, 0, 0)
        m = CATransform3DRotate(m, CGFloat(ry * .pi / 180), 0, 1, 0)
        m = CATransform3DRotate(m, CGFloat(rz * .pi / 180), 0, 0, 1)
        if flipped {
            m = CATransform3DRotate(m, .pi, 0, 1, 0)
            m = CATransform3DTranslate(m, 0, 0, 0.3 * em)
        } else {
            m = CATransform3DTranslate(m, 0, 0, 0.3 * em)
        }
        layer?(&m)
        m = CATransform3DTranslate(m, -size.width / 2, -size.height / 2, 0)
        return m
    }

    /// Placement of every layer this frame.
    func placements(design: ParallaxDesign, size: CGSize, window: CGSize, host: CGSize, em: CGFloat) -> [Placement] {
        let n = design.layers.count
        let parallax = CGFloat(motionParallax(design))
        let sinY = CGFloat(sin(ry * .pi / 180)), sinX = CGFloat(sin(rx * .pi / 180))
        // Spread grid.
        let columns = n <= 4 ? n : Int((Double(n) / 2).rounded(.up))
        let rows = Int((Double(n) / Double(max(columns, 1))).rounded(.up))
        let gridScale = min(0.62, (host.width * 0.94) / (CGFloat(columns) * window.width * 1.1), (host.height * 0.84) / (CGFloat(rows) * window.height * 1.16))
        var out: [Placement] = []
        out.reserveCapacity(n)
        for (j, layer) in design.layers.enumerated() {
            let state = j < layers.count ? layers[j] : LayerState()
            let depth = CGFloat(layer.depth)
            let pops = layer.pops && !layer.fillsWindow
            let open = CGFloat(max(state.stack, state.spread))
            let column = j % max(columns, 1), row = j / max(columns, 1)
            let inRow = row == rows - 1 ? n - row * columns : columns
            let gz = (CGFloat(j) - CGFloat(n - 1) / 2) * 8.6 * em
            let gdx = (CGFloat(column) - CGFloat(inRow - 1) / 2) * window.width * gridScale * 1.1
            let gdy = (CGFloat(row) - CGFloat(rows - 1) / 2) * window.height * gridScale * 1.16
            let popZ: CGFloat = pops ? -depth * em * parallax * 0.7 : 0
            let bob = CGFloat(state.stack) * (CGFloat(sin(time * 1.3 - Double(j) * 0.65)) * 0.45 * em)
            let spreadWave = CGFloat(sin(.pi * min(1, max(0, state.spread))))
            let z = popZ * (1 - open) + (gz + bob) * CGFloat(state.stack) + (CGFloat(j) - CGFloat(n - 1) / 2) * 2.4 * em * spreadWave
            let scale = 1 + (gridScale - 1) * CGFloat(state.spread)
            let yaw = spreadWave * (j % 2 == 1 ? 16 : -16) * CGFloat(spreadBlend)
            let sp = CGFloat(state.spread)
            let transform = cardTransform(size: size, em: em) { m in
                guard open > 0.0005 || pops else { return }
                m = CATransform3DTranslate(m, gdx * sp, gdy * sp, z)
                m = CATransform3DRotate(m, yaw * .pi / 180, 0, 1, 0)
                m = CATransform3DScale(m, scale, scale, 1)
            }
            let travel: CGFloat = pops ? 0 : depth * em * parallax * (1 - open)
            let slide = CGPoint(x: -travel * sinY, y: travel * sinX)
            var cover: CGFloat = 1
            if layer.fillsWindow {
                let reach = 0.5 * abs(depth) * em * parallax
                cover = max(1 + 2 * reach / window.width, 1 + 2 * reach / window.height) + 0.01
                cover = 1 + (cover - 1) * (1 - open)
            }
            let tile = min(1, max(0, CGFloat(state.stack) * 0.06 + pow(CGFloat(state.spread), 4)))
            out.append(Placement(transform: transform, slide: slide, coverScale: cover, open: open, tileOpacity: tile, edgeOpacity: min(1, open * open)))
        }
        return out
    }

    private func motionParallax(_ design: ParallaxDesign) -> Double {
        reduceMotion ? design.motion.parallax * 0.5 : design.motion.parallax
    }
}
