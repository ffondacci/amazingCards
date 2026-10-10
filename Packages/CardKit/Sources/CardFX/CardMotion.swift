import SwiftUI

/// Everything a shader needs to react to the user: where the card is tilted,
/// where the finger is, and the clock for time-based animation.
///
/// Injected in the environment by `cardMotion(...)` / `CardMotionStage`, read
/// by `cardEffect(_:)`.
public struct CardMotion: Equatable, Sendable {
    /// Tilt in −1…1 on both axes. Zero when the card lies flat.
    public var tilt: CGPoint
    /// Finger position normalized to 0…1 inside the card, nil when not touching.
    public var pointer: CGPoint?
    /// Seconds since the motion stage appeared (0 when animation is paused).
    public var time: TimeInterval
    /// True while a gesture is driving the tilt.
    public var isInteracting: Bool

    public init(
        tilt: CGPoint = .zero,
        pointer: CGPoint? = nil,
        time: TimeInterval = 0,
        isInteracting: Bool = false
    ) {
        self.tilt = tilt
        self.pointer = pointer
        self.time = time
        self.isInteracting = isInteracting
    }

    /// Pointer encoded for Metal: negative coordinates mean "no pointer".
    var pointerArgument: CGPoint { pointer ?? CGPoint(x: -1, y: -1) }

    /// Distance of the pointer (or tilt) from the centre, 0…1.
    public var distanceFromCenter: Double {
        let p = pointer.map { CGPoint(x: ($0.x - 0.5) * 2, y: ($0.y - 0.5) * 2) } ?? tilt
        return min(1, hypot(p.x, p.y) / sqrt(2))
    }
}

private struct CardMotionKey: EnvironmentKey {
    static let defaultValue = CardMotion()
}

public extension EnvironmentValues {
    /// Current motion of the enclosing card. Defaults to a still card.
    var cardMotion: CardMotion {
        get { self[CardMotionKey.self] }
        set { self[CardMotionKey.self] = newValue }
    }
}

// MARK: - Injection

/// Animatable modifier: SwiftUI interpolates the tilt, so a spring applied to
/// the state value makes every shader follow the spring frame by frame.
struct CardMotionInjector: ViewModifier, Animatable {
    nonisolated var tiltX: Double
    nonisolated var tiltY: Double
    nonisolated var pointer: CGPoint?
    nonisolated var time: TimeInterval
    nonisolated var isInteracting: Bool

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(tiltX, tiltY) }
        set {
            tiltX = newValue.first
            tiltY = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.environment(
            \.cardMotion,
            CardMotion(
                tilt: CGPoint(x: tiltX, y: tiltY),
                pointer: pointer,
                time: time,
                isInteracting: isInteracting
            )
        )
    }
}

struct CardMotionProvider: ViewModifier {
    var tilt: CGPoint
    var pointer: CGPoint?
    var isInteracting: Bool
    var animates: Bool

    @State private var origin = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !animates || reduceMotion)) { timeline in
            content.modifier(
                CardMotionInjector(
                    tiltX: tilt.x,
                    tiltY: tilt.y,
                    pointer: pointer,
                    time: reduceMotion ? 0 : timeline.date.timeIntervalSince(origin),
                    isInteracting: isInteracting
                )
            )
        }
    }
}

public extension View {
    /// Publishes the motion of a card to its shader effects.
    ///
    /// - Parameters:
    ///   - tilt: −1…1 on both axes. Animate the value you pass (a spring on
    ///     release, for example) and the shaders follow the animation.
    ///   - pointer: normalized finger position, nil when idle.
    ///   - isInteracting: true while a gesture drives the tilt.
    ///   - animates: drives the clock for time-based effects (sparkles, stars).
    ///     Pass false for static thumbnails to save GPU and battery.
    func cardMotion(
        tilt: CGPoint,
        pointer: CGPoint? = nil,
        isInteracting: Bool = false,
        animates: Bool = true
    ) -> some View {
        modifier(CardMotionProvider(tilt: tilt, pointer: pointer, isInteracting: isInteracting, animates: animates))
    }

    /// Publishes a still motion whose clock is running (for animated
    /// previews that nobody touches).
    func cardMotionIdle(animates: Bool = true) -> some View {
        modifier(CardMotionProvider(tilt: .zero, pointer: nil, isInteracting: false, animates: animates))
    }
}
