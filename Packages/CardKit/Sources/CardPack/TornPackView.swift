import CardCore
import CardFX
import CardUI
import SwiftUI

/// Pack rendered as real pieces while its strip is torn: the body (plus the
/// still-attached part of the strip), and the torn part of the strip peeling
/// up around the cut. Masks follow the jagged tear line, the peeled piece
/// casts a shadow on the body and both edges show a fibrous paper rim.
///
/// Drive it with a `TearState` fed by `tearable(..., rendersGap: false)`.
struct TornPackView: View {
    let design: PackDesign
    let width: CGFloat
    let height: CGFloat
    let tear: TearState
    let roughness: CGFloat
    /// After the break: the strip rotates fully and flies off.
    let flyAway: Bool
    /// Vertical offset and opacity of the body (used when the pack drops).
    let bodyOffsetY: CGFloat
    let bodyOpacity: Double

    /// Sparks intensity: 1 while tearing, fading to 0 after the break.
    @State private var sparkIntensity: Double = 0

    private var lineY: CGFloat { height * design.stripFraction }
    private var fromTrailing: Bool { tear.direction.x < 0 }

    /// Torn length along the strip, in points from the start edge.
    private var front: CGFloat {
        guard tear.isActive || tear.isTorn else { return 0 }
        return min(abs(tear.tip.x - tear.origin.x), width)
    }

    private var progress: CGFloat { width > 0 ? min(front / width, 1) : 0 }

    var body: some View {
        let front = flyAway ? width : front
        let progress = progress
        let radius = CurlShader.rollRadius(front: Double(front), stripHeight: Double(lineY))
        let rollCenterX = fromTrailing ? width - front : front

        ZStack {
            // Body and attached strip.
            pack
                .overlay { fibreRim(front: front) }
                .mask {
                    TornPackMask(kind: .body, front: front, lineY: lineY, roughness: roughness, fromTrailing: fromTrailing)
                }
                .offset(y: bodyOffsetY)
                .opacity(bodyOpacity)

            // Shadow of the roll on the body, just under the cut.
            if front > 0.5, !flyAway {
                Ellipse()
                    .fill(.black.opacity(0.45))
                    .frame(width: radius * 2.6, height: 14)
                    .blur(radius: 6)
                    .position(x: rollCenterX, y: lineY + 4)
                    .opacity(min(1, Double(progress) * 4))
                    .allowsHitTesting(false)
            }

            // Torn strip rolling up at the finger. The layer is cropped to
            // the band so the curl shader only touches those pixels.
            if front > 0.5 {
                let bandHeight = lineY + roughness * 1.6 + 2
                pack
                    .overlay { fibreRim(front: front) }
                    .mask {
                        TornPackMask(kind: .strip, front: front, lineY: lineY, roughness: roughness, fromTrailing: fromTrailing)
                    }
                    .frame(width: width, height: bandHeight, alignment: .top)
                    .clipped()
                    .modifier(
                        CurlEffectModifier(
                            lineY: lineY,
                            front: front,
                            fromTrailing: fromTrailing,
                            radius: radius,
                            edgeAllowance: roughness * 1.6
                        )
                    )
                    .frame(width: width, height: height, alignment: .top)
                    .rotationEffect(.degrees(flyAway ? (fromTrailing ? -28 : 28) : 0), anchor: .top)
                    .offset(
                        x: flyAway ? (fromTrailing ? -width * 0.6 : width * 0.6) : 0,
                        y: flyAway ? -height * 0.5 : 0
                    )
                    .opacity(flyAway ? 0 : 1)
                    .animation(.easeIn(duration: 0.6), value: flyAway)
                    .allowsHitTesting(false)
            }

            // Sparks at the cutting point, with an afterglow once the band
            // breaks. The layer overflows the pack so particles fly past
            // its edges; it is an overlay so it does not enlarge the stack.
            if sparkIntensity > 0.01 {
                let overflow: CGFloat = 90
                let sparkX = flyAway ? (fromTrailing ? 0 : width) : rollCenterX
                let layerHeight = lineY + overflow + 220
                Color.clear
                    .frame(width: width, height: height)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(width: width + overflow * 2, height: layerHeight)
                            .offset(y: -overflow)
                            .cardEffect(.sparks(
                                origin: CGPoint(x: sparkX + overflow, y: lineY + overflow),
                                direction: CGPoint(x: fromTrailing ? -1 : 1, y: 0),
                                tint: design.accent,
                                intensity: 1.3 * sparkIntensity
                            ))
                            .cardMotionIdle(animates: true)
                            .blendMode(.plusLighter)
                    }
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .onChange(of: tear.isActive, initial: true) { _, active in
            if active {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { sparkIntensity = 1 }
            } else if !tear.isTorn {
                withAnimation(.easeOut(duration: 0.25)) { sparkIntensity = 0 }
            }
        }
        .onChange(of: tear.isTorn) { _, torn in
            if torn {
                withAnimation(.easeOut(duration: 0.55)) { sparkIntensity = 0 }
            }
        }
    }

    /// The printed pack, rasterized once: every copy below is masked or
    /// curled on every drag event, and compositing a cached texture is
    /// far cheaper than re-rendering text, canvases and shaders.
    private var pack: some View {
        BoosterPackView(design: design)
            .frame(width: width, height: height)
            .cardMotionIdle(animates: false)
            .drawingGroup()
    }

    /// Off-white fibrous line along the cut, half of it clipped by each mask.
    private func fibreRim(front: CGFloat) -> some View {
        TornPackMask(kind: .edge, front: front, lineY: lineY, roughness: roughness, fromTrailing: fromTrailing)
            .stroke(
                Color(red: 0.97, green: 0.96, blue: 0.93).opacity(0.85),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
    }
}

/// Animatable application of `ck_curl` so the roll follows springs.
struct CurlEffectModifier: ViewModifier, Animatable {
    nonisolated var lineY: Double
    nonisolated var front: Double
    nonisolated var fromTrailing: Bool
    nonisolated var radius: Double
    nonisolated var edgeAllowance: Double

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(front, radius) }
        set {
            front = newValue.first
            radius = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.visualEffect { [lineY, front, fromTrailing, radius, edgeAllowance] view, proxy in
            view.layerEffect(
                CurlShader.shader(
                    size: proxy.size,
                    lineY: lineY,
                    front: front,
                    fromTrailing: fromTrailing,
                    radius: radius,
                    edgeAllowance: edgeAllowance
                ),
                maxSampleOffset: CGSize(width: proxy.size.width, height: 0),
                isEnabled: front > 0.5
            )
        }
    }
}

/// Masks and strokes derived from the jagged tear line.
struct TornPackMask: Shape {
    enum Kind: Sendable {
        /// Everything except the torn part of the strip.
        case body
        /// The torn part of the strip only.
        case strip
        /// Open path along the cut, for the fibre rim.
        case edge
        /// Band under the cut, for the cast shadow.
        case shadow
    }

    var kind: Kind
    var front: CGFloat
    var lineY: CGFloat
    var roughness: CGFloat
    var fromTrailing: Bool

    var animatableData: CGFloat {
        get { front }
        set { front = newValue }
    }

    private func edgeY(_ x: CGFloat, in rect: CGRect) -> CGFloat {
        let along = fromTrailing ? rect.maxX - x : x - rect.minX
        let coarse = CGFloat(TearShader.edgeOffset(at: Double(along))) * roughness
        let fine = CGFloat(TearShader.fibreOffset(at: Double(along))) * roughness * 0.45
        return lineY + rect.minY - (coarse + fine)
    }

    private func cutPoints(in rect: CGRect) -> [CGPoint] {
        let length = min(max(front, 0), rect.width)
        let steps = max(Int(length / 1.5), 2)
        return (0...steps).map { i in
            let along = length * CGFloat(i) / CGFloat(steps)
            let x = fromTrailing ? rect.maxX - along : rect.minX + along
            return CGPoint(x: x, y: edgeY(x, in: rect))
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cut = cutPoints(in: rect)
        guard let first = cut.first, let last = cut.last else { return path }
        let startX = fromTrailing ? rect.maxX : rect.minX
        switch kind {
        case .body:
            // Start on the start edge at the cut, follow the cut to the front,
            // go up to the top edge, around the whole pack, back to the start.
            path.move(to: first)
            for point in cut.dropFirst() { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: rect.minY))
            if fromTrailing {
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            } else {
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            }
            path.addLine(to: CGPoint(x: startX, y: first.y))
            path.closeSubpath()
        case .strip:
            let farX = fromTrailing ? rect.minX : rect.maxX
            path.move(to: CGPoint(x: startX, y: rect.minY))
            path.addLine(to: CGPoint(x: farX, y: rect.minY))
            path.addLine(to: CGPoint(x: farX, y: lineY + rect.minY))
            path.addLine(to: CGPoint(x: last.x, y: lineY + rect.minY))
            for point in cut.reversed() { path.addLine(to: point) }
            path.closeSubpath()
        case .edge:
            path.move(to: first)
            for point in cut.dropFirst() { path.addLine(to: point) }
        case .shadow:
            path.move(to: first)
            for point in cut.dropFirst() { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: last.y + 14))
            path.addLine(to: CGPoint(x: startX, y: first.y + 14))
            path.closeSubpath()
        }
        return path
    }
}

#Preview("Peeling strip") {
    let design = PackDesign(
        title: "Van Gogh",
        subtitle: "Masterpieces",
        setCode: "S1",
        cover: .asset("starry_night"),
        topColor: CardColor(hex: 0x1B2A6B),
        bottomColor: CardColor(hex: 0x0D1230),
        accent: .gold,
        foilHue: 0.6,
        emblemSymbol: "paintpalette.fill"
    )
    let state = TearState()
    let width: CGFloat = 320
    let height = width / PackDesign.aspectRatio
    state.viewSize = CGSize(width: width, height: height)
    state.origin = CGPoint(x: 0, y: height * 0.17)
    state.tip = CGPoint(x: 210, y: height * 0.17)
    state.direction = CGPoint(x: 1, y: 0)
    state.isActive = true
    return ZStack {
        Color(white: 0.08)
        TornPackView(design: design, width: width, height: height, tear: state, roughness: 5, flyAway: false, bodyOffsetY: 0, bodyOpacity: 1)
    }
    .frame(width: 420, height: 600)
}
