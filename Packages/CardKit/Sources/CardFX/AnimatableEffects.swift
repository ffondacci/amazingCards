import CardCore
import SwiftUI

// Shader arguments are not animatable by themselves: SwiftUI only interpolates
// `Animatable` modifiers. These wrappers expose the parameter that should be
// animated as `animatableData`, so `withAnimation { progress = 1 }` works.

/// Animatable light sweep. Animate `progress` from 0 to 1.
public struct CardSweepModifier: ViewModifier, Animatable {
    public nonisolated var progress: Double
    public nonisolated var intensity: Double
    public nonisolated var width: Double
    public nonisolated var angle: Double

    public nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public func body(content: Content) -> some View {
        content.cardEffect(
            .sweep(progress: progress, intensity: intensity, width: width, angle: angle),
            isEnabled: progress > 0 && progress < 1
        )
    }
}

/// Animatable dissolve. Animate `progress` 0 → 1 to burn the view away, or
/// 1 → 0 to make it appear.
public struct CardDissolveModifier: ViewModifier, Animatable {
    public nonisolated var progress: Double
    public nonisolated var edgeWidth: Double
    public nonisolated var edgeColor: CardColorValue
    public nonisolated var scale: Double

    public nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public func body(content: Content) -> some View {
        content.cardEffect(
            .dissolve(progress: progress, edgeWidth: edgeWidth, edgeColor: edgeColor.value, scale: scale),
            isEnabled: progress > 0
        )
    }
}

/// Animatable ripple distortion. Animate `elapsed` from 0 to ~2 seconds.
public struct CardRippleModifier: ViewModifier, Animatable {
    public nonisolated var elapsed: Double
    public nonisolated var center: CGPoint
    public nonisolated var amplitude: Double
    public nonisolated var frequency: Double

    public nonisolated var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    nonisolated static func shader(size: CGSize, center: CGPoint, elapsed: Double, amplitude: Double, frequency: Double) -> Shader {
        Shader(
            function: CardFXShaders.function("ck_ripple"),
            arguments: [.float2(size), .float2(center), .float(elapsed), .float(amplitude), .float(frequency)]
        )
    }

    public func body(content: Content) -> some View {
        content.visualEffect { [elapsed, center, amplitude, frequency] view, proxy in
            view.distortionEffect(
                Self.shader(size: proxy.size, center: center, elapsed: elapsed, amplitude: amplitude, frequency: frequency),
                maxSampleOffset: CGSize(width: amplitude, height: amplitude),
                isEnabled: elapsed > 0 && elapsed < 3
            )
        }
    }
}

/// Wrapper so `CardColor` can live in an `Animatable` modifier without
/// taking part in the animation.
public struct CardColorValue: Hashable, Sendable {
    public var value: CardCore.CardColor
    public init(_ value: CardCore.CardColor) { self.value = value }
}

public extension View {
    /// Light band crossing the view. Animate `progress` 0 → 1.
    func cardSweep(progress: Double, intensity: Double = 0.7, width: Double = 0.16, angle: Double = 35) -> some View {
        modifier(CardSweepModifier(progress: progress, intensity: intensity, width: width, angle: angle))
    }

    /// Noise dissolve with a glowing edge. Animate `progress` 0 → 1.
    func cardDissolve(progress: Double, edgeWidth: Double = 0.08, edgeColor: CardColor = .gold, scale: Double = 6) -> some View {
        modifier(CardDissolveModifier(progress: progress, edgeWidth: edgeWidth, edgeColor: CardColorValue(edgeColor), scale: scale))
    }

    /// Radial ripple from `center` (local points). Animate `elapsed` 0 → 2.
    func cardRipple(center: CGPoint, elapsed: Double, amplitude: Double = 10, frequency: Double = 0.12) -> some View {
        modifier(CardRippleModifier(elapsed: elapsed, center: center, amplitude: amplitude, frequency: frequency))
    }
}
