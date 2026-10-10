import CardCore
import CardFX
import CardUI
import SwiftUI

/// The whole opening experience: tear the strip of a sealed pack, watch the
/// cards slide out, then swipe through them. Foil cards react to the finger,
/// rare pulls get a burst behind them.
public struct PackOpeningView: View {
    public var design: PackDesign
    public var onFinished: ([Card]) -> Void
    /// Pair with a `matchedGeometryEffect` on the pack shown elsewhere (a
    /// carousel, a shop) so the pack travels to the centre when opened.
    public var packTransition: (id: AnyHashable, namespace: Namespace.ID)?

    @State private var model: PackOpeningModel
    @State private var shakeCount = 0
    /// False while the pack travels from where it was tapped; the deck
    /// behind it is kept invisible until the pack has settled.
    @State private var packSettled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        pack: BoosterPack,
        design: PackDesign,
        packTransition: (id: AnyHashable, namespace: Namespace.ID)? = nil,
        onFinished: @escaping ([Card]) -> Void = { _ in }
    ) {
        self.design = design
        self.packTransition = packTransition
        self.onFinished = onFinished
        self._model = State(initialValue: PackOpeningModel(pack: pack))
    }

    public var body: some View {
        GeometryReader { proxy in
            // The pack is a hair larger than the cards: nothing shows until it opens.
            let cardWidth = min(proxy.size.width * 0.72, proxy.size.height * 0.6 * CardMetrics.aspectRatio)
            let packWidth = cardWidth * 1.05
            let packHeight = packWidth / PackDesign.aspectRatio
            ZStack {
                background(size: proxy.size)
                cardsLayer(cardWidth: cardWidth, packHeight: packHeight, size: proxy.size)
                packLayer(width: packWidth, height: packHeight, size: proxy.size)
                hints(size: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .finished { onFinished(model.revealed) }
        }
        .task {
            // Matched-geometry arrival of the pack takes about half a second.
            try? await Task.sleep(for: .milliseconds(packTransition == nil ? 0 : 550))
            packSettled = true
        }
        .onDisappear { model.cancel() }
        .sensoryFeedback(.success, trigger: model.phase == .torn)
        .sensoryFeedback(.levelChange, trigger: model.currentCard?.id)
    }

    // MARK: Layers

    private func background(size: CGSize) -> some View {
        let rare = model.currentCard.map { $0.rarity >= .rare } ?? false
        let tint = model.currentCard?.rarity.color ?? .gold
        return ZStack {
            Rectangle()
                .fill(.black)
                .cardEffect(.starfield(density: 26, intensity: 0.8))
            Rectangle()
                .fill(.black)
                .cardEffect(.burst(tint: tint, intensity: rare ? 0.9 : 0))
                .opacity(rare ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: rare)
        }
        .cardMotionIdle(animates: !reduceMotion)
        .ignoresSafeArea()
    }

    /// One stack for the whole flow: hidden inside the pack, rising out of
    /// it, then centred and flipping card by card. No view is swapped, so
    /// nothing flashes between phases.
    private func cardsLayer(cardWidth: CGFloat, packHeight: CGFloat, size: CGSize) -> some View {
        let phase = model.phase
        let insidePack = phase == .sealed || phase == .torn
        let emerging = phase == .emerging
        let revealed = phase == .browsing || phase == .finished
        let offset: CGFloat = insidePack ? 0 : (emerging ? -packHeight * 0.36 : 0)
        return VStack(spacing: 16) {
            CardSwipeStack(
                cards: model.pack.cards,
                index: $model.topIndex,
                revealsFaces: revealed,
                deckStyle: true
            ) { card, _ in
                model.cardSwiped(card)
            }
            .frame(width: cardWidth)
            .scaleEffect(insidePack ? 0.9 : 1)
            .offset(y: offset)
            .opacity(packSettled ? 1 : 0)
            .animation(.spring(response: 0.8, dampingFraction: 0.78), value: phase)
            .allowsHitTesting(revealed)
            if phase == .finished {
                summary
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: phase)
    }

    private func packLayer(width: CGFloat, height: CGFloat, size: CGSize) -> some View {
        let phase = model.phase
        let gone = phase == .browsing || phase == .finished
        let bodyOffset: CGFloat = gone ? size.height * 0.9 : (phase == .emerging ? height * 0.42 : 0)
        return TornPackView(
            design: design,
            width: width,
            height: height,
            tear: model.tear,
            roughness: 5,
            flyAway: phase != .sealed,
            bodyOffsetY: bodyOffset,
            bodyOpacity: gone ? 0 : 1
        )
        .modifier(MatchedPack(transition: packTransition, isActive: phase == .sealed))
        .animation(.spring(response: 0.75, dampingFraction: 0.85), value: phase)
        .cardShake(trigger: shakeCount, amplitude: 8)
        .tearable(
            .topStrip(height: design.stripFraction, maxGap: width * 0.12, rendersGap: false),
            state: model.tear
        ) {
            model.packTorn()
        }
        .onTapGesture { if phase == .sealed { shakeCount += 1 } }
        .accessibilityAction(named: "Open the pack") { model.openImmediately() }
        .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
        .zIndex(gone ? 0 : 2)
    }

    private func hints(size: CGSize) -> some View {
        VStack {
            Spacer()
            Group {
                switch model.phase {
                case .sealed:
                    Label("Tear the strip from one edge", systemImage: "hand.draw.fill")
                case .torn, .emerging:
                    Label("Opening…", systemImage: "sparkles")
                case .browsing:
                    Label("Swipe to reveal · \(min(model.topIndex + 1, model.pack.count)) / \(model.pack.count)", systemImage: "hand.point.up.left.and.text.fill")
                case .finished:
                    EmptyView()
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(0.12)))
            .padding(.bottom, 24)
            .animation(.easeInOut, value: model.phase)
        }
        .allowsHitTesting(false)
    }

    private var summary: some View {
        let best = model.pack.cards.max { $0.rarity < $1.rarity }
        return VStack(spacing: 6) {
            Text("\(model.pack.count) cards added")
                .font(.headline)
            if let best {
                HStack(spacing: 6) {
                    RaritySymbol(best.rarity, size: 14)
                    Text("Best pull: \(best.title) · \(best.rarity.displayName)")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.12)))
    }
}

/// Applies the optional matched geometry of the pack.
private struct MatchedPack: ViewModifier {
    let transition: (id: AnyHashable, namespace: Namespace.ID)?
    let isActive: Bool

    func body(content: Content) -> some View {
        if let transition {
            content.matchedGeometryEffect(id: transition.id, in: transition.namespace, isSource: isActive)
        } else {
            content
        }
    }
}
