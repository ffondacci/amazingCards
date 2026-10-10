import CardCore
import CardFX
import SwiftUI

/// Constraints of a tear gesture.
public enum TearDirection: Hashable, Sendable {
    /// Locked to the first 12 pt of the drag.
    case any
    /// Left ↔ right only, started from the leading or trailing edge.
    case horizontal
    /// Top ↔ bottom only, started from the top or bottom edge.
    case vertical
}

/// Tunables of `tearable(...)`.
public struct TearConfiguration: Hashable, Sendable {
    public var direction: TearDirection
    /// Distance from an edge (points) within which a drag may start a tear.
    public var edgeThreshold: CGFloat
    /// Widest opening of the cut, at its origin (points).
    public var maxGap: CGFloat
    /// Amplitude of the jagged edge (points).
    public var roughness: CGFloat
    /// Fraction of the path that must be torn before release to break.
    public var breakThreshold: CGFloat
    /// Fraction (0…1) of the perpendicular axis the cut snaps to, nil = free.
    public var snapLine: CGFloat?
    /// Region (unit coordinates) where the drag must start, nil = anywhere near an edge.
    public var startRegion: CGRect?
    /// Extra displacement of the negative side (strip side), 0…1.
    public var lift: CGFloat
    /// When false the modifier only drives `TearState`; the host renders the
    /// pieces itself (see `TornPackView`).
    public var rendersGap: Bool

    public init(
        direction: TearDirection = .any,
        edgeThreshold: CGFloat = 48,
        maxGap: CGFloat = 26,
        roughness: CGFloat = 5,
        breakThreshold: CGFloat = 0.8,
        snapLine: CGFloat? = nil,
        startRegion: CGRect? = nil,
        lift: CGFloat = 0.6,
        rendersGap: Bool = true
    ) {
        self.direction = direction
        self.edgeThreshold = edgeThreshold
        self.maxGap = maxGap
        self.roughness = roughness
        self.breakThreshold = breakThreshold
        self.snapLine = snapLine
        self.startRegion = startRegion
        self.lift = lift
        self.rendersGap = rendersGap
    }

    /// Horizontal tear across a strip at the top of the view.
    public static func topStrip(height fraction: CGFloat = 0.18, maxGap: CGFloat = 24, rendersGap: Bool = true) -> TearConfiguration {
        TearConfiguration(
            direction: .horizontal,
            edgeThreshold: 60,
            maxGap: maxGap,
            roughness: 5,
            breakThreshold: 0.72,
            snapLine: fraction,
            startRegion: CGRect(x: 0, y: 0, width: 1, height: fraction + 0.1),
            lift: 1.0,
            rendersGap: rendersGap
        )
    }
}

/// Observable state of a tear in progress. Public so hosts can mirror the
/// tear (for example to animate a strip flying away after the break).
@MainActor
@Observable
public final class TearState {
    public internal(set) var origin: CGPoint = .zero
    public internal(set) var tip: CGPoint = .zero
    public internal(set) var direction: CGPoint = .zero
    public internal(set) var gap: CGFloat = 0
    public internal(set) var progress: CGFloat = 0
    public internal(set) var isActive = false
    public internal(set) var isTorn = false
    public internal(set) var viewSize: CGSize = .zero
    var maxLength: CGFloat = 1
    var lockedStart: CGPoint?

    public init() {}

    func reset() {
        origin = .zero
        tip = .zero
        direction = .zero
        gap = 0
        progress = 0
        isActive = false
        isTorn = false
        lockedStart = nil
        maxLength = 1
    }
}

/// Animatable application of the tear shader.
struct TearEffectModifier: ViewModifier, Animatable {
    nonisolated var origin: CGPoint
    nonisolated var tipX: Double
    nonisolated var tipY: Double
    nonisolated var gap: Double
    nonisolated var roughness: Double
    nonisolated var lift: Double
    nonisolated var isEnabled: Bool

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(tipX, tipY), gap) }
        set {
            tipX = newValue.first.first
            tipY = newValue.first.second
            gap = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.visualEffect { [origin, tipX, tipY, gap, roughness, lift, isEnabled] view, proxy in
            view.layerEffect(
                TearShader.shader(
                    size: proxy.size,
                    origin: origin,
                    tip: CGPoint(x: tipX, y: tipY),
                    gap: gap,
                    roughness: roughness,
                    lift: lift
                ),
                maxSampleOffset: CGSize(width: gap * (1 + lift) + roughness * 2, height: gap * (1 + lift) + roughness * 2),
                isEnabled: isEnabled && gap > 0.05
            )
        }
    }
}

struct TearGestureModifier: ViewModifier {
    let configuration: TearConfiguration
    let state: TearState
    let onProgress: ((CGFloat) -> Void)?
    let onTorn: () -> Void

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { state.viewSize = $0 }
            .modifier(
                TearEffectModifier(
                    origin: state.origin,
                    tipX: state.tip.x,
                    tipY: state.tip.y,
                    gap: state.gap,
                    roughness: configuration.roughness,
                    lift: configuration.lift,
                    isEnabled: configuration.rendersGap && (state.isActive || state.isTorn)
                )
            )
            .gesture(gesture)
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard !state.isTorn else { return }
                if !state.isActive {
                    guard begin(at: value.startLocation) else { return }
                }
                update(with: value.location, start: value.startLocation)
            }
            .onEnded { _ in
                guard state.isActive, !state.isTorn else { return }
                if state.progress >= configuration.breakThreshold {
                    breakApart()
                } else {
                    recover()
                }
            }
    }

    /// Starts a tear if the touch began near an allowed edge. Returns false otherwise.
    private func begin(at start: CGPoint) -> Bool {
        let size = state.viewSize
        guard size.width > 0, size.height > 0 else { return false }
        if let region = configuration.startRegion {
            let unit = CGPoint(x: start.x / size.width, y: start.y / size.height)
            guard region.contains(unit) else { return false }
        }
        let threshold = configuration.edgeThreshold
        let nearLeading = start.x < threshold
        let nearTrailing = start.x > size.width - threshold
        let nearTop = start.y < threshold
        let nearBottom = start.y > size.height - threshold

        var direction = CGPoint.zero
        var origin = start
        switch configuration.direction {
        case .horizontal:
            if nearLeading { direction = CGPoint(x: 1, y: 0); origin.x = 0 }
            else if nearTrailing { direction = CGPoint(x: -1, y: 0); origin.x = size.width }
            else { return false }
            if let snap = configuration.snapLine { origin.y = snap * size.height }
            state.maxLength = size.width
        case .vertical:
            if nearTop { direction = CGPoint(x: 0, y: 1); origin.y = 0 }
            else if nearBottom { direction = CGPoint(x: 0, y: -1); origin.y = size.height }
            else { return false }
            if let snap = configuration.snapLine { origin.x = snap * size.width }
            state.maxLength = size.height
        case .any:
            guard nearLeading || nearTrailing || nearTop || nearBottom else { return false }
            // Direction is locked later, once the finger has moved a little.
            state.lockedStart = start
        }
        state.origin = origin
        state.tip = origin
        state.direction = direction
        state.gap = 0
        state.progress = 0
        state.isActive = true
        return true
    }

    private func update(with location: CGPoint, start: CGPoint) {
        if state.direction == .zero {
            // Free direction: lock after 12 pt and ray-cast back to the edge.
            let dx = location.x - start.x, dy = location.y - start.y
            let distance = hypot(dx, dy)
            guard distance > 12 else { return }
            let direction = CGPoint(x: dx / distance, y: dy / distance)
            state.direction = direction
            state.origin = rayToEdge(from: start, direction: CGPoint(x: -direction.x, y: -direction.y))
            let far = rayToEdge(from: state.origin, direction: direction)
            state.maxLength = max(hypot(far.x - state.origin.x, far.y - state.origin.y), 1)
            state.tip = state.origin
        }
        let d = state.direction
        let along = (location.x - state.origin.x) * d.x + (location.y - state.origin.y) * d.y
        let clamped = min(max(along, 0), state.maxLength)
        state.tip = CGPoint(x: state.origin.x + d.x * clamped, y: state.origin.y + d.y * clamped)
        state.progress = clamped / state.maxLength
        state.gap = min(clamped / 60, 1) * configuration.maxGap
        onProgress?(state.progress)
    }

    private func breakApart() {
        let d = state.direction
        withAnimation(.easeOut(duration: 0.18)) {
            state.tip = CGPoint(x: state.origin.x + d.x * state.maxLength * 1.05, y: state.origin.y + d.y * state.maxLength * 1.05)
            state.gap = configuration.maxGap
            state.progress = 1
        }
        state.isTorn = true
        state.isActive = false
        onProgress?(1)
        onTorn()
    }

    private func recover() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            state.tip = state.origin
            state.gap = 0
            state.progress = 0
        }
        state.isActive = false
        onProgress?(0)
    }

    private func rayToEdge(from origin: CGPoint, direction: CGPoint) -> CGPoint {
        let w = state.viewSize.width, h = state.viewSize.height
        var best = CGFloat.greatestFiniteMagnitude
        if direction.x != 0 {
            for edge in [CGFloat(0), w] {
                let t = (edge - origin.x) / direction.x
                let y = origin.y + t * direction.y
                if t > 0, y >= 0, y <= h { best = min(best, t) }
            }
        }
        if direction.y != 0 {
            for edge in [CGFloat(0), h] {
                let t = (edge - origin.y) / direction.y
                let x = origin.x + t * direction.x
                if t > 0, x >= 0, x <= w { best = min(best, t) }
            }
        }
        guard best < .greatestFiniteMagnitude else { return origin }
        return CGPoint(x: origin.x + best * direction.x, y: origin.y + best * direction.y)
    }
}

public extension View {
    /// Drag from an edge to tear the view like paper. The tear snaps back
    /// when released early and breaks when `breakThreshold` is reached.
    ///
    /// - Parameters:
    ///   - configuration: direction, gap, roughness, thresholds.
    ///   - state: observable state, create one to mirror the tear elsewhere.
    ///   - onProgress: 0…1 while dragging.
    ///   - onTorn: called once when the view breaks.
    func tearable(
        _ configuration: TearConfiguration = TearConfiguration(),
        state: TearState,
        onProgress: ((CGFloat) -> Void)? = nil,
        onTorn: @escaping () -> Void
    ) -> some View {
        modifier(TearGestureModifier(configuration: configuration, state: state, onProgress: onProgress, onTorn: onTorn))
    }
}

/// Jagged horizontal edge matching the tear shader, to split a torn view
/// into two real pieces. `lineY` is the cut position in points.
public struct TornEdgeShape: Shape {
    public enum Side: Sendable { case above, below }

    public var lineY: CGFloat
    public var roughness: CGFloat
    public var side: Side
    public var fromTrailing: Bool

    public init(lineY: CGFloat, roughness: CGFloat, side: Side, fromTrailing: Bool = false) {
        self.lineY = lineY
        self.roughness = roughness
        self.side = side
        self.fromTrailing = fromTrailing
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = max(Int(rect.width / 1.5), 16)
        func edgeY(_ x: CGFloat) -> CGFloat {
            let along = fromTrailing ? rect.maxX - x : x
            let jag = CGFloat(TearShader.edgeOffset(at: Double(along))) * roughness
            return lineY + (fromTrailing ? jag : -jag)
        }
        // Fine fibres on top of the coarse waves (same noise as the shader).
        func fibreY(_ x: CGFloat) -> CGFloat {
            let along = fromTrailing ? rect.maxX - x : x
            let f = CGFloat(TearShader.fibreOffset(at: Double(along))) * roughness * 0.45
            return fromTrailing ? f : -f
        }
        if side == .above {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            for i in stride(from: steps, through: 0, by: -1) {
                let x = rect.minX + rect.width * CGFloat(i) / CGFloat(steps)
                path.addLine(to: CGPoint(x: x, y: edgeY(x) + fibreY(x)))
            }
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            for i in 0...steps {
                let x = rect.minX + rect.width * CGFloat(i) / CGFloat(steps)
                path.addLine(to: CGPoint(x: x, y: edgeY(x) + fibreY(x)))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview("Tear in progress") {
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
    ZStack {
        Color(white: 0.08)
        BoosterPackView(design: design)
            .frame(width: 320, height: 320 / PackDesign.aspectRatio)
            .cardMotionIdle(animates: false)
            .modifier(
                TearEffectModifier(
                    origin: CGPoint(x: 0, y: 447 * 0.17),
                    tipX: 215,
                    tipY: 447 * 0.17,
                    gap: 30,
                    roughness: 5,
                    lift: 1,
                    isEnabled: true
                )
            )
    }
    .frame(width: 420, height: 560)
}

#Preview("Torn pieces") {
    let design = PackDesign(
        title: "Deep Sky",
        subtitle: "Observatory",
        setCode: "S1",
        cover: .asset("pillars_of_creation"),
        topColor: CardColor(hex: 0x2A0845),
        bottomColor: CardColor(hex: 0x05020F),
        accent: .nebula,
        foilHue: 0.8,
        emblemSymbol: "moon.stars.fill"
    )
    let height = 320 / PackDesign.aspectRatio
    ZStack {
        Color(white: 0.08)
        BoosterPackView(design: design)
            .frame(width: 320, height: height)
            .cardMotionIdle(animates: false)
            .mask { TornEdgeShape(lineY: height * 0.17, roughness: 5, side: .above) }
            .rotation3DEffect(.degrees(-50), axis: (x: 1, y: 0, z: 0), anchor: UnitPoint(x: 0.5, y: 0.17), perspective: 0.7)
            .offset(y: -30)
        BoosterPackView(design: design)
            .frame(width: 320, height: height)
            .cardMotionIdle(animates: false)
            .mask { TornEdgeShape(lineY: height * 0.17, roughness: 5, side: .below) }
            .offset(y: 30)
    }
    .frame(width: 420, height: 600)
}
