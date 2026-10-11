import CardCore
import SwiftUI

/// The card plate behind the window.
struct ParallaxPlate: View {
    let frame: ParallaxFrame
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(frame.plate.mixed(with: .white, 0.04)), Color(frame.plate.mixed(with: .black, 0.35))],
                startPoint: UnitPoint(x: 0.41, y: 0), endPoint: UnitPoint(x: 0.59, y: 1)
            ))
    }
}

/// The thin line and inner shade around the window.
struct ParallaxWindowLine: View {
    let style: ParallaxStyle
    let frame: ParallaxFrame
    let radius: CGFloat
    let em: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if style == .neon {
                shape.strokeBorder(Color(frame.edge2).opacity(0.35), lineWidth: 1.2 * em).blur(radius: 0.6 * em)
                shape.strokeBorder(Color(frame.line).opacity(0.45), lineWidth: 1)
            } else {
                shape.strokeBorder(Color(frame.plate).opacity(0.35), lineWidth: 0.55 * em)
                shape.strokeBorder(Color(frame.line).opacity(0.22), lineWidth: 1)
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

/// Neon tube around the card, glowing in the frame's three colours.
struct ParallaxNeonFrame: View {
    let frame: ParallaxFrame
    let radius: CGFloat
    let em: CGFloat
    let thin: Bool
    let time: TimeInterval

    var body: some View {
        let width = (thin ? 0.09 : 0.2) * em
        let glow = max(0, min(2, CGFloat(frame.glow)))
        let hum = 0.91 + 0.09 * cos(time * 2 * .pi / 4.5)
        RoundedRectangle(cornerRadius: max(0, radius - width / 2), style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [Color(frame.edge1), Color(frame.edge2), Color(frame.edge3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: width
            )
            .shadow(color: glow > 0 ? Color(frame.edge2).opacity(0.9) : .clear, radius: 0.35 * glow * em)
            .shadow(color: glow > 0 ? Color(frame.edge2).opacity(0.55) : .clear, radius: 1.3 * glow * em)
            .opacity(thin ? 0.8 : hum)
            .allowsHitTesting(false)
    }
}

/// Rim line of a poster card.
struct ParallaxRimLine: View {
    let frame: ParallaxFrame
    let radius: CGFloat
    let em: CGFloat

    var body: some View {
        let glow = max(0, min(2, CGFloat(frame.glow)))
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color(frame.line).opacity(0.22), lineWidth: 1)
            .shadow(color: glow > 0 ? Color(frame.edge1).opacity(0.55) : .clear, radius: 1.4 * glow * em)
            .allowsHitTesting(false)
    }
}

/// Darkens the corners of the window.
struct ParallaxVignette: View {
    let shade: CardColor
    let size: CGSize

    var body: some View {
        EllipticalGradient(stops: [.init(color: .clear, location: 0.6), .init(color: Color(shade).opacity(0.55), location: 1)])
            .frame(width: size.width * 1.2, height: size.height * 0.95)
            .position(x: size.width / 2, y: size.height * 0.45)
            .frame(width: size.width, height: size.height)
            .clipped()
            .allowsHitTesting(false)
    }
}

/// Light on the glass, following the pointer and the turn of the card.
struct ParallaxGlare: View {
    let color: CardColor
    let size: CGSize
    /// Centre of the pool (0…1) and position of the band (0…1).
    let pool: CGPoint
    let band: CGFloat
    let opacity: CGFloat

    var body: some View {
        ZStack {
            EllipticalGradient(colors: [Color(color).opacity(0.28), .clear])
                .frame(width: size.width * 1.2, height: size.height * 0.9)
                .position(x: pool.x * size.width, y: pool.y * size.height)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: max(0, band - 0.14)),
                    .init(color: Color(color).opacity(0.12), location: band),
                    .init(color: .clear, location: min(1, band + 0.14)),
                ],
                startPoint: UnitPoint(x: 0.1, y: 0), endPoint: UnitPoint(x: 0.9, y: 1)
            )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .blendMode(.screen)
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

/// The back of the card.
struct ParallaxBackFace: View {
    let design: ParallaxDesign
    let size: CGSize
    let radius: CGFloat
    let em: CGFloat
    let time: TimeInterval

    var body: some View {
        let back = design.back
        let pulse = 0.78 + 0.22 * (1 - cos(time * 2 * .pi / 5)) / 2
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(back.edge))
            EllipticalGradient(
                stops: [
                    .init(color: Color(back.background), location: 0),
                    .init(color: Color(back.background.mixed(with: back.edge, 0.6)), location: 0.6),
                    .init(color: Color(back.edge), location: 1),
                ]
            )
            .frame(width: size.width * 1.4, height: size.height)
            .position(x: size.width / 2, y: size.height * 0.45)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            RoundedRectangle(cornerRadius: 1.2 * em, style: .continuous)
                .strokeBorder(Color(design.frame.line).opacity(0.35), lineWidth: 1)
                .padding(1.6 * em)
            RoundedRectangle(cornerRadius: 0.8 * em, style: .continuous)
                .strokeBorder(Color(design.frame.line).opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3 * em / 10, 3 * em / 10]))
                .opacity(0.5)
                .padding(2.3 * em)
            VStack(spacing: 0) {
                ZStack {
                    EllipticalGradient(stops: [
                        .init(color: Color(back.accent).opacity(0.55), location: 0),
                        .init(color: Color(back.accent).opacity(0.2), location: 0.5),
                        .init(color: .clear, location: 0.75),
                    ])
                    .frame(width: 25.5 * em, height: 25.5 * em)
                    .opacity(pulse)
                    Circle()
                        .strokeBorder(Color(back.accent).opacity(0.35), lineWidth: 1)
                        .frame(width: 20 * em, height: 20 * em)
                        .shadow(color: Color(back.accent).opacity(0.35), radius: 1.2 * em)
                    if let id = back.pictureLayer, let layer = design.layers.first(where: { $0.id == id }), case .image(let image) = layer.content {
                        ArtworkView(image.artwork, contentMode: .fit)
                            .mask {
                                if image.keyedOnBlack { ArtworkView(image.artwork, contentMode: .fit).luminanceToAlpha() } else { Rectangle() }
                            }
                            .frame(width: 17 * em, height: 17 * em / CGFloat(max(image.aspect, 0.05)))
                            .shadow(color: Color(back.accent).opacity(0.65), radius: em)
                    } else {
                        ParallaxBadge()
                            .stroke(Color(back.titleColor), lineWidth: 0.4 * em)
                            .frame(width: 10.2 * em, height: 12.2 * em)
                            .shadow(color: Color(back.accent).opacity(0.8), radius: 1.2 * em)
                    }
                }
                .frame(width: 17 * em, height: 17 * em)
                Text(back.title)
                    .font(.system(size: 2.1 * em, weight: .semibold, design: .rounded))
                    .tracking(0.25 * em)
                    .foregroundStyle(Color(back.titleColor))
                    .padding(.top, 1.1 * em)
                Text(back.subtitle.uppercased())
                    .font(.system(size: 0.62 * em, weight: .medium))
                    .tracking(0.26 * em)
                    .foregroundStyle(Color(back.subtitleColor).opacity(0.75))
                    .padding(.top, 0.6 * em)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 2 * em)
            if design.style == .neon {
                ParallaxNeonFrame(frame: design.frame, radius: radius, em: em, thin: false, time: time)
            } else {
                ParallaxRimLine(frame: design.frame, radius: radius, em: em)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Specks

/// Floating specks drawn over the window, each at its own depth.
@MainActor
final class ParallaxSpeckField {
    struct Speck {
        var depth: Double
        var x: Double, y: Double
        var vx: Double = 0, vy: Double = 0
        var size: Double
        var sway: Double = 0, swayRate: Double = 0, phase: Double = 0
        var twinkle: Double = 0, twinklePhase: Double = 0
        var age: Double = 0, life: Double = 1
        var flash: Double = 0
        var color: Int
    }

    private(set) var specks: [Speck] = []
    private var kind: ParallaxSpecks.Kind = .none
    private var count: Double = 1
    private var spawn: Double = 0
    private var clock: Double = 0
    private var lastNow: TimeInterval?

    private func random(_ a: Double, _ b: Double) -> Double { a + Double.random(in: 0..<1) * (b - a) }
    private func depth() -> Double { Double.random(in: 0..<1) < 0.2 ? random(-2.5, -0.4) : random(1.5, 8) }
    private func size(_ d: Double) -> Double { d < 0 ? random(1.5, 2.4) : random(0.85, 1.6) * (1.15 - d * 0.05) }
    private func color() -> Int { let t = Double.random(in: 0..<1); return t < 0.55 ? 0 : t < 0.85 ? 1 : 2 }

    private func make(_ kind: ParallaxSpecks.Kind, fromTop: Bool) -> Speck {
        let d = depth()
        switch kind {
        case .twinkle:
            return Speck(depth: d, x: random(0.02, 0.98), y: random(0.02, 0.98), vy: random(-0.006, -0.002), size: size(d) * 1.15, life: random(1.2, 3.2), color: color())
        case .glitter:
            let v = random(0.16, 0.3) * (d < 0 ? 1.35 : 1.05 - d * 0.05)
            return Speck(depth: d, x: fromTop ? random(-0.35, 1) : random(-0.2, 1.1), y: fromTop ? random(-0.12, -0.02) : random(-0.05, 1.05), vx: v * 0.32, vy: v, size: size(d) * 0.9, twinkle: random(3, 7), twinklePhase: random(0, 6.3), color: color())
        default:
            return Speck(depth: d, x: random(-0.05, 1.05), y: fromTop ? random(-0.08, -0.01) : random(-0.05, 1.05), vy: random(0.035, 0.075) * (d < 0 ? 1.5 : 1.1 - d * 0.06), size: size(d), sway: random(0.004, 0.012), swayRate: random(0.5, 1.3), phase: random(0, 6.3), twinkle: random(1.5, 4), twinklePhase: random(0, 6.3), color: color())
        }
    }

    func configure(_ settings: ParallaxSpecks) {
        guard settings.kind != kind || settings.count != count else { return }
        kind = settings.kind
        count = settings.count
        specks = []
        spawn = 0
        switch kind {
        case .stardust: for _ in 0..<Int((170 * count).rounded()) { specks.append(make(.stardust, fromTop: false)) }
        case .twinkle:
            for _ in 0..<Int((70 * count).rounded()) {
                var s = make(.twinkle, fromTop: false)
                s.age = random(0, s.life)
                specks.append(s)
            }
        case .glitter: for _ in 0..<Int((140 * count).rounded()) { specks.append(make(.glitter, fromTop: false)) }
        case .none: break
        }
    }

    /// Moves every speck to `now`.
    func update(now: TimeInterval, speed: Double) {
        let dt = lastNow.map { min(0.05, max(0, now - $0)) } ?? 0
        lastNow = now
        guard kind != .none else { return }
        let e = dt * speed
        clock += e
        if kind == .twinkle {
            spawn += e * 28 * count
            while spawn >= 1, specks.count < Int(110 * count) {
                specks.append(make(.twinkle, fromTop: false))
                spawn -= 1
            }
        }
        var i = specks.count - 1
        while i >= 0 {
            var s = specks[i]
            switch kind {
            case .stardust:
                s.y += s.vy * e
                s.x += sin(clock * s.swayRate + s.phase) * s.sway * e
                if s.y > 1.08 { specks[i] = make(.stardust, fromTop: true); i -= 1; continue }
            case .twinkle:
                s.age += e
                s.y += s.vy * e
                if s.age >= s.life { specks.remove(at: i); i -= 1; continue }
            case .glitter:
                s.x += s.vx * e
                s.y += s.vy * e
                if s.y > 1.1 || s.x > 1.1 { specks[i] = make(.glitter, fromTop: true); i -= 1; continue }
                if s.flash <= 0, Double.random(in: 0..<1) < e * 0.35 { s.flash = 1 }
                s.flash = max(0, s.flash - e * 3.5)
            case .none: break
            }
            specks[i] = s
            i -= 1
        }
    }

    /// Draws every speck with its parallax slide.
    func draw(in context: inout GraphicsContext, window: CGSize, em: CGFloat, parallax: Double, sinY: Double, sinX: Double, settings: ParallaxSpecks) {
        guard kind != .none else { return }
        let colors = settings.colors.map { Color($0) }
        for s in specks {
            var alpha: Double = 1
            var size = s.size * settings.size
            switch kind {
            case .stardust:
                alpha = (0.7 + 0.3 * sin(clock * s.twinkle + s.twinklePhase)) * min(1, (s.y + 0.08) / 0.1, (1.08 - s.y) / 0.12)
            case .twinkle:
                let k = sin(.pi * s.age / s.life)
                alpha = k * k
                size *= 0.6 + 0.4 * alpha
            case .glitter:
                alpha = (0.45 + 0.35 * sin(clock * s.twinkle + s.twinklePhase) + s.flash * 0.9) * min(1, (s.y + 0.12) / 0.1)
                size *= 1 + s.flash * 1.4
            case .none: break
            }
            let far = min(1, max(0, s.depth / 8))
            alpha *= 1 - far * 0.3
            guard alpha > 0.01 else { continue }
            let travel = s.depth * Double(em) * parallax
            let x = s.x * Double(window.width) - travel * sinY
            let y = s.y * Double(window.height) + travel * sinX
            let diameter = size * 4.2
            let color = colors[min(s.color, max(0, colors.count - 1))]
            let a = min(1, alpha)
            let rect = CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(a * 0.55)))
            let core = diameter * 0.42
            context.fill(Path(ellipseIn: CGRect(x: x - core / 2, y: y - core / 2, width: core, height: core)), with: .color(.white.opacity(a)))
        }
    }
}

/// The glass plate a layer stands on when the card is pulled apart.
struct ParallaxTile: View {
    let frame: ParallaxFrame
    let radius: CGFloat
    let em: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(frame.plate.mixed(with: .black, 0.15)))
            .overlay {
                // Faint checker, like a cutting mat.
                Canvas { context, size in
                    let step = 0.8 * em
                    guard step > 1 else { return }
                    var path = Path()
                    var y: CGFloat = 0
                    var row = 0
                    while y < size.height {
                        var x: CGFloat = row % 2 == 0 ? 0 : step
                        while x < size.width {
                            path.addRect(CGRect(x: x, y: y, width: step, height: step))
                            x += 2 * step
                        }
                        y += step
                        row += 1
                    }
                    context.fill(path, with: .color(.white.opacity(0.035)))
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .allowsHitTesting(false)
    }
}

/// Outline of a layer's plate.
struct ParallaxTileEdge: View {
    let radius: CGFloat
    let em: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.stroke(.black.opacity(0.22), lineWidth: 1).padding(-0.5)
            shape.strokeBorder(.white.opacity(0.6), lineWidth: 1)
            shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0.07), location: 0), .init(color: .clear, location: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .shadow(color: Color(red: 0.04, green: 0.04, blue: 0.12).opacity(0.18), radius: 1.6 * em, y: 0.6 * em)
        .allowsHitTesting(false)
    }
}
