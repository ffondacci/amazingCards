import CardCore
import CardFX
import QuartzCore
import SwiftUI

/// A card whose layers slide apart as it tilts: drag it to turn it, tap it
/// twice to flip it, or show its layers pulled apart (`mode`). Fits the
/// space it is given, keeping the 2:3 ratio of the design.
public struct ParallaxCardView: View {
    public var design: ParallaxDesign
    public var mode: ParallaxMode
    /// Bump to flip the card.
    public var flips: Int
    /// Scale of the card inside its host (0.6…1.3).
    public var size: Double

    @State private var engine = ParallaxEngine()
    @State private var specks = ParallaxSpeckField()
    @State private var active = true
    @State private var dragging = false
    @Environment(\.cardMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(design: ParallaxDesign, mode: ParallaxMode = .card, flips: Int = 0, size: Double = 1) {
        self.design = design
        self.mode = mode
        self.flips = flips
        self.size = size
    }

    /// Sizes of the card in its host, all derived from the host.
    struct Geometry {
        var host: CGSize
        var card: CGSize
        var window: CGSize
        var em: CGFloat
        var inset: CGFloat
        var radius: CGFloat
        var windowRadius: CGFloat

        init(host: CGSize, design: ParallaxDesign, size: Double) {
            self.host = host
            let width = max(80, min(host.width * 0.74, host.height * 0.84 / 1.5) * CGFloat(min(2, max(0.3, size))))
            card = CGSize(width: width, height: width * 1.5)
            em = width / 40
            inset = design.style == .neon ? 0.85 * em : 0
            window = CGSize(width: card.width - 2 * inset, height: card.height - 2 * inset)
            radius = CGFloat(design.frame.cornerRadius) * width
            windowRadius = design.style == .neon ? radius * 0.63 : radius
        }
    }

    /// Everything one frame needs, computed once from the engine.
    struct FrameState {
        var now: TimeInterval
        var placements: [ParallaxEngine.Placement]
        var open: CGFloat
        var showsFront: Bool
        var cardTransform: ProjectionTransform
        var backTransform: ProjectionTransform
        var context: ParallaxLayerContext
        var parallax: Double
        var sinY: Double
        var sinX: Double
        var glarePool: CGPoint
        var glareBand: CGFloat
        var glareOpacity: CGFloat
    }

    public var body: some View {
        GeometryReader { proxy in
            let geometry = Geometry(host: proxy.size, design: design, size: size)
            TimelineView(.animation(paused: !active)) { timeline in
                let state = makeState(now: timeline.date.timeIntervalSinceReferenceDate, geometry: geometry)
                ZStack {
                    if state.showsFront {
                        plate(state, geometry)
                        layers(state, geometry)
                        glass(state, geometry)
                        chrome(state, geometry)
                    } else {
                        ParallaxBackFace(design: design, size: geometry.card, radius: geometry.radius, em: geometry.em, time: state.now)
                            .projectionEffect(state.backTransform)
                    }
                }
                .frame(width: geometry.card.width, height: geometry.card.height)
                .position(x: geometry.host.width / 2, y: geometry.host.height / 2)
            }
            .frame(width: geometry.host.width, height: geometry.host.height)
            .contentShape(Rectangle())
            .gesture(drag(geometry))
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): engine.pointer(at: point, cardWidth: geometry.card.width, center: CGPoint(x: geometry.host.width / 2, y: geometry.host.height / 2))
                case .ended: engine.pointer(at: nil, cardWidth: geometry.card.width, center: .zero)
                }
            }
        }
        .onChange(of: mode, initial: true) { _, mode in engine.show(mode, time: Date.timeIntervalSinceReferenceDate) }
        .onChange(of: flips) { _, _ in engine.flip() }
        .onChange(of: motion.tilt, initial: true) { _, tilt in engine.deviceTilt(tilt) }
        .onChange(of: reduceMotion, initial: true) { _, value in engine.reduceMotion = value }
        .onChange(of: design.frame.specks, initial: true) { _, value in specks.configure(value) }
        .onAppear { active = true }
        .onDisappear { active = false }
        .accessibilityLabel(design.name)
    }

    private func drag(_ g: Geometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let now = value.time.timeIntervalSinceReferenceDate
                if !dragging {
                    dragging = true
                    engine.dragBegan(at: value.startLocation, time: now)
                }
                engine.dragChanged(to: value.location, cardWidth: g.card.width, center: CGPoint(x: g.host.width / 2, y: g.host.height / 2), time: now)
            }
            .onEnded { value in
                dragging = false
                engine.dragEnded(time: value.time.timeIntervalSinceReferenceDate)
            }
    }

    // MARK: - One frame

    private func makeState(now: TimeInterval, geometry g: Geometry) -> FrameState {
        engine.step(now: now, motion: design.motion, layerCount: design.layers.count)
        specks.update(now: now, speed: design.frame.specks.speed)
        let placements = engine.placements(design: design, size: g.card, window: g.window, host: g.host, em: g.em)
        let open = CGFloat(engine.openness)
        let turn = engine.turn
        let sheenX = CGFloat(min(0.84, max(0.1, (47 - turn * 1.15 + engine.rx * 0.6) / 100)))
        let sheenAlpha = CGFloat((1 - Double(open)) * min(1, abs(turn) / 18 + abs(engine.rx) / 36))
        let hovering = engine.hover > 0
        let pool = CGPoint(
            x: hovering ? 0.5 + CGFloat(engine.hx) * 0.45 : 0.5 - CGFloat(turn) * 0.022,
            y: hovering ? 0.35 + CGFloat(engine.hy) * 0.4 : 0.28 + CGFloat(engine.rx) * 0.025
        )
        let glare = design.motion.glare * (0.6 + 0.8 * min(1, abs(turn) / 18 + engine.hover * 0.4))
        return FrameState(
            now: now,
            placements: placements,
            open: open,
            showsFront: engine.showsFront || open > 0.02,
            cardTransform: ProjectionTransform(engine.cardTransform(size: g.card, em: g.em)),
            backTransform: ProjectionTransform(engine.cardTransform(size: g.card, em: g.em, flipped: true)),
            context: ParallaxLayerContext(window: g.window, em: g.em, sheenX: sheenX, sheenAlpha: sheenAlpha, time: now, reduceMotion: reduceMotion),
            parallax: reduceMotion ? design.motion.parallax * 0.5 : design.motion.parallax,
            sinY: sin(engine.ry * .pi / 180),
            sinX: sin(engine.rx * .pi / 180),
            glarePool: pool,
            glareBand: CGFloat(min(1, max(0, (50 - turn * 2.6) / 100))),
            glareOpacity: CGFloat(glare) * (1 - open)
        )
    }

    private func plate(_ state: FrameState, _ g: Geometry) -> some View {
        ZStack {
            ParallaxPlate(frame: design.frame, radius: g.radius)
            RoundedRectangle(cornerRadius: g.windowRadius, style: .continuous)
                .fill(Color(design.frame.plate))
                .padding(g.inset)
        }
        .frame(width: g.card.width, height: g.card.height)
        .opacity(1 - state.open)
        .projectionEffect(state.cardTransform)
    }

    private func layers(_ state: FrameState, _ g: Geometry) -> some View {
        ForEach(Array(design.layers.enumerated()), id: \.element.id) { index, layer in
            let placement = state.placements[index]
            let pops = layer.pops && !layer.fillsWindow
            ZStack {
                ParallaxTile(frame: design.frame, radius: g.windowRadius, em: g.em)
                    .opacity(placement.tileOpacity)
                ParallaxLayerContent(layer: layer, context: state.context)
                    .frame(width: g.window.width, height: g.window.height)
                    .scaleEffect(placement.coverScale)
                    .offset(x: placement.slide.x, y: placement.slide.y)
                    .frame(width: g.window.width, height: g.window.height)
                    .modifier(WindowClip(radius: g.windowRadius, enabled: !pops))
                    .opacity(layer.opacity)
                ParallaxTileEdge(radius: g.windowRadius, em: g.em)
                    .opacity(placement.edgeOpacity)
            }
            .frame(width: g.window.width, height: g.window.height)
            .frame(width: g.card.width, height: g.card.height)
            .projectionEffect(ProjectionTransform(placement.transform))
        }
    }

    private func glass(_ state: FrameState, _ g: Geometry) -> some View {
        ZStack {
            if design.frame.specks.kind != .none {
                Canvas(opaque: false, rendersAsynchronously: false) { gc, _ in
                    specks.draw(in: &gc, window: g.window, em: g.em, parallax: state.parallax, sinY: state.sinY, sinX: state.sinX, settings: design.frame.specks)
                }
                .allowsHitTesting(false)
            }
            ParallaxVignette(shade: design.frame.shade, size: g.window)
            ParallaxGlare(color: design.motion.glareColor, size: g.window, pool: state.glarePool, band: state.glareBand, opacity: state.glareOpacity)
            ParallaxWindowLine(style: design.style, frame: design.frame, radius: g.windowRadius, em: g.em)
        }
        .frame(width: g.window.width, height: g.window.height)
        .clipShape(RoundedRectangle(cornerRadius: g.windowRadius, style: .continuous))
        .opacity(1 - state.open)
        .frame(width: g.card.width, height: g.card.height)
        .projectionEffect(state.cardTransform)
    }

    private func chrome(_ state: FrameState, _ g: Geometry) -> some View {
        ZStack {
            if design.style == .neon {
                ParallaxNeonFrame(frame: design.frame, radius: g.radius, em: g.em, thin: false, time: state.now)
            } else {
                ParallaxRimLine(frame: design.frame, radius: g.radius, em: g.em)
                ParallaxNeonFrame(frame: design.frame, radius: g.radius, em: g.em, thin: true, time: state.now)
            }
        }
        .frame(width: g.card.width, height: g.card.height)
        .opacity(1 - state.open)
        .projectionEffect(state.cardTransform)
    }
}

/// Clips a layer to the window unless it stands out of it.
private struct WindowClip: ViewModifier {
    let radius: CGFloat
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content
        }
    }
}
