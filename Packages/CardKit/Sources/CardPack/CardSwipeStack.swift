import CardCore
import CardFX
import CardUI
import SwiftUI

/// Direction a card left the stack.
public enum SwipeDirection: Sendable {
    case left, right
}

/// Stack of cards: drag the top one sideways to throw it out, the next one
/// springs in. The top card tilts with the finger so its foil reacts.
public struct CardSwipeStack: View {
    public var cards: [Card]
    @Binding public var index: Int
    public var visibleDepth: Int
    /// When false every card shows its back (a sealed deck). When true the
    /// top card flips face up, and so does each next card as it comes up.
    public var revealsFaces: Bool
    /// Cards under the top one show their backs (a deck) instead of faces.
    public var deckStyle: Bool
    public var onSwipe: (Card, SwipeDirection) -> Void

    @State private var drag: CGSize = .zero
    @State private var pointer: CGPoint?
    @State private var isDragging = false
    @State private var size: CGSize = .zero
    @State private var topIsFaceUp = false

    public init(
        cards: [Card],
        index: Binding<Int>,
        visibleDepth: Int = 3,
        revealsFaces: Bool = true,
        deckStyle: Bool = false,
        onSwipe: @escaping (Card, SwipeDirection) -> Void = { _, _ in }
    ) {
        self.cards = cards
        self._index = index
        self.visibleDepth = visibleDepth
        self.revealsFaces = revealsFaces
        self.deckStyle = deckStyle
        self.onSwipe = onSwipe
    }

    private var visible: [(offset: Int, card: Card)] {
        guard index < cards.count else { return [] }
        let end = min(cards.count, index + visibleDepth)
        return (index..<end).map { ($0 - index, cards[$0]) }
    }

    public var body: some View {
        ZStack {
            ForEach(visible.reversed(), id: \.card.id) { position, card in
                let isTop = position == 0
                let faceUp = isTop ? (revealsFaces && topIsFaceUp) : !deckStyle
                FlipContainer(isFaceUp: faceUp) {
                    CardView(card: card, showsFinish: position < 2)
                } back: {
                    CardBackView()
                }
                    .cardMotion(
                        tilt: isTop ? topTilt : .zero,
                        pointer: isTop ? pointer : nil,
                        isInteracting: isTop && isDragging,
                        animates: isTop
                    )
                    .cardTilt(isTop ? topTilt : .zero, maxRotation: 12)
                    .scaleEffect(1 - CGFloat(position) * 0.05)
                    .offset(y: CGFloat(position) * size.height * 0.035)
                    .offset(isTop ? drag : .zero)
                    .rotationEffect(.degrees(isTop ? drag.width / 18 : 0))
                    .shadow(color: .black.opacity(isTop ? 0.4 : 0.2), radius: size.width * 0.04, y: size.width * 0.02)
                    .zIndex(Double(visibleDepth - position))
                    .animation(.spring(response: 0.45, dampingFraction: 0.78), value: index)
                    .allowsHitTesting(isTop)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .gesture(dragGesture, including: revealsFaces ? .all : .subviews)
        .task(id: RevealKey(index: index, reveals: revealsFaces)) {
            // Each card that comes on top flips face up after a short beat,
            // cancelled automatically if the stack moves on or disappears.
            guard revealsFaces else {
                topIsFaceUp = false
                return
            }
            try? await Task.sleep(for: .milliseconds(index == 0 ? 220 : 120))
            guard !Task.isCancelled else { return }
            withAnimation(.cardFlip) { topIsFaceUp = true }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: index)
        .accessibilityElement(children: .contain)
    }

    private var topTilt: CGPoint {
        guard size.width > 0 else { return .zero }
        var tilt = CGPoint(
            x: max(-1, min(1, drag.width / (size.width * 0.45))),
            y: max(-1, min(1, drag.height / (size.height * 0.45)))
        )
        if let pointer, isDragging {
            tilt.x = max(-1, min(1, tilt.x * 0.5 + (pointer.x - 0.5) * 1.2))
            tilt.y = max(-1, min(1, tilt.y * 0.5 + (pointer.y - 0.5) * 1.2))
        }
        return tilt
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard index < cards.count, size.width > 0 else { return }
                withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
                    drag = value.translation
                    pointer = CGPoint(
                        x: min(max(value.startLocation.x / size.width, 0), 1),
                        y: min(max(value.startLocation.y / size.height, 0), 1)
                    )
                    isDragging = true
                }
            }
            .onEnded { value in
                guard index < cards.count else { return }
                let projected = value.predictedEndTranslation.width
                let threshold = size.width * 0.32
                if abs(projected) > threshold || abs(drag.width) > threshold {
                    let direction: SwipeDirection = projected > 0 ? .right : .left
                    throwOut(direction)
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
                        drag = .zero
                        isDragging = false
                    }
                    pointer = nil
                }
            }
    }

    private func throwOut(_ direction: SwipeDirection) {
        let card = cards[index]
        let sign: CGFloat = direction == .right ? 1 : -1
        withAnimation(.easeOut(duration: 0.28)) {
            drag = CGSize(width: sign * size.width * 1.6, height: drag.height * 1.3 - 40)
            isDragging = false
        }
        pointer = nil
        onSwipe(card, direction)
        // Advance once the card has left the screen; `.task` style delay is
        // cancellable through the view lifetime of the stack.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                drag = .zero
                topIsFaceUp = false
            }
            index += 1
        }
    }

    private struct RevealKey: Hashable {
        var index: Int
        var reveals: Bool
    }
}
