import CardCore
import CardFX
import SwiftUI

// MARK: - Idle float

private struct IdleFloatModifier: ViewModifier {
    let amplitude: CGFloat
    let period: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator([false, true]) { view, phase in
                view
                    .offset(y: phase ? -amplitude : amplitude)
                    .rotationEffect(.degrees(phase ? 1.2 : -1.2))
            } animation: { _ in
                .easeInOut(duration: period)
            }
        }
    }
}

// MARK: - Shake

private struct ShakeModifier: ViewModifier {
    let trigger: AnyHashable
    let amplitude: CGFloat

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGSize.zero, trigger: trigger) { view, value in
            view
                .offset(x: value.width)
                .rotationEffect(.degrees(value.height))
        } keyframes: { _ in
            KeyframeTrack(\.width) {
                SpringKeyframe(amplitude, duration: 0.08)
                SpringKeyframe(-amplitude * 0.8, duration: 0.08)
                SpringKeyframe(amplitude * 0.5, duration: 0.08)
                SpringKeyframe(-amplitude * 0.25, duration: 0.08)
                SpringKeyframe(0, duration: 0.12)
            }
            KeyframeTrack(\.height) {
                SpringKeyframe(2.5, duration: 0.08)
                SpringKeyframe(-2, duration: 0.08)
                SpringKeyframe(1, duration: 0.08)
                SpringKeyframe(0, duration: 0.16)
            }
        }
    }
}

// MARK: - Dissolve transition

/// Insert/remove with a noise burn. Use with `.transition(.cardDissolve())`.
public struct CardDissolveTransition: Transition {
    public nonisolated var edgeColor: CardColor

    public nonisolated init(edgeColor: CardColor = .gold) {
        self.edgeColor = edgeColor
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .cardDissolve(progress: phase.isIdentity ? 0 : 1, edgeWidth: 0.1, edgeColor: edgeColor, scale: 7)
            .scaleEffect(phase.isIdentity ? 1 : 0.96)
    }
}

public extension AnyTransition {
    /// Dissolve transition packaged for `.transition(_:)` call sites that need `AnyTransition`.
    static func cardDissolve(edgeColor: CardColor = .gold) -> AnyTransition {
        AnyTransition(CardDissolveTransition(edgeColor: edgeColor))
    }
}

public extension Transition where Self == CardDissolveTransition {
    static func cardDissolve(edgeColor: CardColor = .gold) -> CardDissolveTransition {
        CardDissolveTransition(edgeColor: edgeColor)
    }
}

// MARK: - View API

public extension View {
    /// Gentle endless levitation (paused with Reduce Motion).
    func cardIdleFloat(amplitude: CGFloat = 5, period: Double = 2.4) -> some View {
        modifier(IdleFloatModifier(amplitude: amplitude, period: period))
    }

    /// Quick side-to-side shake each time `trigger` changes.
    func cardShake(trigger: some Hashable & Sendable, amplitude: CGFloat = 10) -> some View {
        modifier(ShakeModifier(trigger: AnyHashable(trigger), amplitude: amplitude))
    }
}

// MARK: - Fan

/// Cards held like a hand, spread along an arc. Tap a card to raise it.
public struct CardFanView: View {
    public var cards: [Card]
    public var spreadDegrees: Double
    public var selectedID: CardID?
    public var onSelect: (Card) -> Void

    public init(
        cards: [Card],
        spreadDegrees: Double = 40,
        selectedID: CardID? = nil,
        onSelect: @escaping (Card) -> Void = { _ in }
    ) {
        self.cards = cards
        self.spreadDegrees = spreadDegrees
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { proxy in
            let count = max(cards.count, 1)
            let cardWidth = min(proxy.size.width * 0.42, proxy.size.height * 0.62 * CardMetrics.aspectRatio)
            let radius = cardWidth * 1.7
            ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    let t = count == 1 ? 0 : (Double(index) / Double(count - 1) - 0.5)
                    let angle = t * spreadDegrees
                    let isSelected = card.id == selectedID
                    CardView(card: card, showsFinish: isSelected)
                        .frame(width: cardWidth)
                        .shadow(color: .black.opacity(0.35), radius: cardWidth * 0.05, y: cardWidth * 0.03)
                        .offset(y: isSelected ? -cardWidth * 0.35 : 0)
                        .rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.5, y: 1 + radius / (cardWidth / CardMetrics.aspectRatio)))
                        .zIndex(isSelected ? 100 : Double(index))
                        .onTapGesture { onSelect(card) }
                        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: selectedID)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
