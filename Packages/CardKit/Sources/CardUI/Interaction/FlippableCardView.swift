import CardCore
import CardFX
import SwiftUI

/// Card that flips between its back and its face with a 3D rotation.
/// Bind `isFaceUp` and animate changes; tap toggles when `flipsOnTap`.
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
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) {
                isFaceUp.toggle()
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Flips the card")
    }
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

/// Animatable core of the flip: shows the front below 90°, the back above.
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
        let showsFront = angle < 90
        ZStack {
            front
                .opacity(showsFront ? 1 : 0)
                .accessibilityHidden(!showsFront)
            back
                .rotation3DEffect(.degrees(180), axis: rotationAxis)
                .opacity(showsFront ? 0 : 1)
                .accessibilityHidden(showsFront)
        }
        .rotation3DEffect(.degrees(angle), axis: rotationAxis, perspective: 0.55)
    }
}
