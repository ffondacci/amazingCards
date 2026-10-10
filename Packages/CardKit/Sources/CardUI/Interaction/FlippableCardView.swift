import CardCore
import CardFX
import SwiftUI

/// Card that flips between its back and its face. The flip is a "pop": the
/// card lifts and grows while it spins on a soft spring that overshoots,
/// the back is visible mid-turn and the foil reacts to the rotation.
public struct FlippableCardView: View {
    public var card: Card
    @Binding public var isFaceUp: Bool
    public var flipsOnTap: Bool
    public var axis: Axis

    public init(card: Card, isFaceUp: Binding<Bool>, flipsOnTap: Bool = true, axis: Axis = .horizontal) {
        self.card = card
        self._isFaceUp = isFaceUp
        self.flipsOnTap = flipsOnTap
        self.axis = axis
    }

    public var body: some View {
        FlipContainer(isFaceUp: isFaceUp, axis: axis) {
            CardView(card: card)
        } back: {
            CardBackView()
        }
        .aspectRatio(CardMetrics.aspectRatio, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            guard flipsOnTap else { return }
            withAnimation(.cardFlip) { isFaceUp.toggle() }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Flips the card")
    }
}

public extension Animation {
    /// Soft spring with a visible overshoot, the signature feel of the flip.
    static let cardFlip = Animation.spring(response: 0.95, dampingFraction: 0.58)
}

/// Generic two-sided flip, reusable for packs or tokens.
public struct FlipContainer<Front: View, Back: View>: View {
    public var isFaceUp: Bool
    public var axis: Axis
    private let front: Front
    private let back: Back

    public init(isFaceUp: Bool, axis: Axis = .horizontal, @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.isFaceUp = isFaceUp
        self.axis = axis
        self.front = front()
        self.back = back()
    }

    public var body: some View {
        FlipEffectContainer(angle: isFaceUp ? 0 : 180, axis: axis, front: front, back: back)
    }
}

/// Animatable core of the flip: shows the front below 90°, the back above,
/// pops the scale at mid-turn and feeds the rotation to the foil shaders.
private struct FlipEffectContainer<Front: View, Back: View>: View, Animatable {
    nonisolated var angle: Double
    nonisolated var axis: Axis
    let front: Front
    let back: Back

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    private var rotationAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        axis == .horizontal ? (0, 1, 0) : (1, 0, 0)
    }

    var body: some View {
        // 0 at rest on either face, 1 at mid-turn (also during the overshoot).
        let turn = abs(sin(angle * .pi / 180))
        let showsFront = ((angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) < 90
            || ((angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) > 270
        ZStack {
            front
                .opacity(showsFront ? 1 : 0)
                .accessibilityHidden(!showsFront)
            back
                .rotation3DEffect(.degrees(180), axis: rotationAxis)
                .opacity(showsFront ? 0 : 1)
                .accessibilityHidden(showsFront)
        }
        .transformEnvironment(\.cardMotion) { motion in
            // The light sweeps across the foil as the card turns.
            let lean = sin(angle * .pi / 180) * 0.9
            if axis == .horizontal {
                motion.tilt.x = max(-1, min(1, motion.tilt.x + lean))
            } else {
                motion.tilt.y = max(-1, min(1, motion.tilt.y + lean))
            }
        }
        .rotation3DEffect(.degrees(angle), axis: rotationAxis, perspective: 0.55)
        .scaleEffect(1 + turn * 0.07)
        .shadow(color: .black.opacity(0.35 * turn), radius: 18 * turn, y: 14 * turn)
    }
}
