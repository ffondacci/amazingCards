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

    @State private var model: PackOpeningModel
    @State private var shakeCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(pack: BoosterPack, design: PackDesign, onFinished: @escaping ([Card]) -> Void = { _ in }) {
        self.design = design
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

    private func cardsLayer(cardWidth: CGFloat, packHeight: CGFloat, size: CGSize) -> some View {
        let phase = model.phase
        let insidePack = phase == .sealed || phase == .torn
        let stackOffset: CGFloat = insidePack ? 0 : -packHeight * 0.36
        return ZStack {
            if phase != .browsing && phase != .finished {
                ZStack {
                    ForEach(Array(model.pack.cards.prefix(5).enumerated()), id: \.element.id) { index, _ in
                        CardBackView()
                            .frame(width: cardWidth * 0.9)
                            .rotationEffect(.degrees(Double(index - 2) * (phase == .emerging ? 4 : 0)))
                            .offset(y: CGFloat(index) * (phase == .emerging ? -6 : 0))
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                            .animation(
                                .spring(response: 0.7, dampingFraction: 0.75).delay(Double(index) * 0.07),
                                value: phase
                            )
                    }
                }
                .offset(y: stackOffset)
                .scaleEffect(insidePack ? 0.9 : 1)
                .animation(.spring(response: 0.8, dampingFraction: 0.78), value: phase)
                .transition(.opacity)
            }
            if phase == .browsing || phase == .finished {
                VStack(spacing: 16) {
                    CardSwipeStack(cards: model.pack.cards, index: $model.topIndex) { card, _ in
                        model.cardSwiped(card)
                    }
                    .frame(width: cardWidth)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    if phase == .finished {
                        summary
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
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
