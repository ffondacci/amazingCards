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
    /// Frame (global coordinates) the pack was tapped in, for example from
    /// `PackCarouselView`: the pack flies from there to the centre.
    public var arrivesFrom: CGRect?

    @State private var model: PackOpeningModel
    @State private var shakeCount = 0
    /// 0 = pack still at `arrivesFrom`, 1 = at rest. Animated by a spring.
    @State private var flightProgress: Double = 0
    /// The deck behind the pack stays invisible until the pack has settled.
    @State private var packSettled = false
    @State private var sounds = PackSoundscape()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Plays the procedural wrapper sounds (crinkle, tear, whoosh).
    public var playsSound: Bool

    public init(
        pack: BoosterPack,
        design: PackDesign,
        arrivesFrom: CGRect? = nil,
        playsSound: Bool = true,
        onFinished: @escaping ([Card]) -> Void = { _ in }
    ) {
        self.design = design
        self.arrivesFrom = arrivesFrom
        self.playsSound = playsSound
        self.onFinished = onFinished
        self._model = State(initialValue: PackOpeningModel(pack: pack))
    }

    public var body: some View {
        GeometryReader { proxy in
            // The pack is a hair larger than the cards: nothing shows until it opens.
            let cardWidth = min(proxy.size.width * 0.72, proxy.size.height * 0.6 * CardMetrics.aspectRatio)
            let packWidth = cardWidth * 1.05
            let packHeight = packWidth / PackDesign.aspectRatio
            let container = proxy.frame(in: .global)
            let resting = CGRect(
                x: container.midX - packWidth / 2,
                y: container.midY - packHeight / 2,
                width: packWidth,
                height: packHeight
            )
            ZStack {
                background(size: proxy.size)
                cardsLayer(cardWidth: cardWidth, packHeight: packHeight, size: proxy.size)
                packLayer(width: packWidth, height: packHeight, size: proxy.size, resting: resting)
                hints(size: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .torn { sounds.whoosh() }
            if phase == .finished { onFinished(model.revealed) }
        }
        .task {
            guard playsSound else { return }
            await sounds.start()
            sounds.crinkle(strength: 0.6)
        }
        .onDisappear { sounds.stop() }
        .task {
            var still = Transaction()
            still.disablesAnimations = true
            guard let arrivesFrom, arrivesFrom.width > 0, !reduceMotion else {
                withTransaction(still) {
                    flightProgress = 1
                    packSettled = true
                }
                return
            }
            // Let a couple of frames render at the source, then fly. The deck
            // shows once the spring has mostly settled.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            var flight = Transaction(animation: .spring(response: 0.62, dampingFraction: 0.8))
            flight.disablesAnimations = false
            withTransaction(flight) { flightProgress = 1 }
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }
            withTransaction(still) { packSettled = true }
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
                .renderScale(0.5)
            if rare {
                Rectangle()
                    .fill(.black)
                    .cardEffect(.burst(tint: tint, intensity: 0.9))
                    .renderScale(0.5)
                    .transition(.opacity.animation(.easeInOut(duration: 0.6)))
            }
        }
        .cardMotionIdle(animates: !reduceMotion, minimumInterval: 1 / 30)
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
            .transaction { if !packSettled { $0.animation = nil } }
            .animation(.spring(response: 0.8, dampingFraction: 0.78), value: phase)
            .allowsHitTesting(revealed)
            if phase == .finished {
                summary
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: phase)
    }

    private func packLayer(width: CGFloat, height: CGFloat, size: CGSize, resting: CGRect) -> some View {
        let phase = model.phase
        let gone = phase == .browsing || phase == .finished
        let bodyOffset: CGFloat = gone ? size.height * 0.9 : (phase == .emerging ? height * 0.42 : 0)
        let sealed = phase == .sealed || phase == .torn
        return TornPackView(
            design: design,
            width: width,
            height: height,
            tear: model.tear,
            roughness: 5,
            flyAway: phase != .sealed,
            bodyOffsetY: bodyOffset,
            bodyOpacity: gone ? 0 : 1,
            bulge: sealed ? 1 : 0,
            mouthOpen: phase == .emerging ? 1 : (gone ? 0.6 : 0)
        )
        .background {
            // Static blurred shape instead of a content shadow: the pack is
            // re-rendered on every drag event and a real shadow would be too.
            RoundedRectangle(cornerRadius: width * 0.035, style: .continuous)
                .fill(.black.opacity(0.55))
                .padding(.top, height * design.stripFraction * (phase == .sealed ? 0 : 1))
                .blur(radius: 16)
                .offset(y: bodyOffset + 12)
                .opacity(gone ? 0 : 1)
        }
        .modifier(PackFlight(source: arrivesFrom, resting: resting, progress: flightProgress))
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
        .background { TearFeedback(tear: model.tear, sounds: sounds) }
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

/// Animatable scale + offset between a source frame and the resting frame,
/// both in global coordinates. `progress` 0 = at the source, 1 = at rest.
private struct PackFlight: ViewModifier, Animatable {
    nonisolated var source: CGRect?
    nonisolated var resting: CGRect
    nonisolated var progress: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let flies = (source?.width ?? 0) > 0 && resting.width > 0
        let t = flies ? min(max(progress, 0), 1) : 1
        let scale: CGFloat = flies ? (source!.width / resting.width) * (1 - t) + t : 1
        let offset: CGSize = flies
            ? CGSize(width: (source!.midX - resting.midX) * (1 - t), height: (source!.midY - resting.midY) * (1 - t))
            : .zero
        content
            .scaleEffect(scale)
            .offset(offset)
    }
}

/// Haptic ticks and tearing sound along the cut, isolated so only this
/// view observes the tear progress (the rest of the screen is not
/// re-evaluated per event).
private struct TearFeedback: View {
    let tear: TearState
    let sounds: PackSoundscape

    @State private var lastProgress: CGFloat = 0
    @State private var lastTime: ContinuousClock.Instant = .now

    var body: some View {
        Color.clear
            .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.45), trigger: Int(tear.progress * 14))
            .onChange(of: tear.isActive) { _, active in
                if active {
                    sounds.crinkle(strength: 0.9)
                    lastProgress = tear.progress
                    lastTime = .now
                } else {
                    sounds.tearing(speed: 0)
                }
            }
            .onChange(of: tear.progress) { _, progress in
                guard tear.isActive else { return }
                let now = ContinuousClock.Instant.now
                let seconds = max((now - lastTime).seconds, 0.004)
                let speed = Double(abs(progress - lastProgress)) / seconds
                lastProgress = progress
                lastTime = now
                sounds.tearing(speed: min(speed / 1.8, 1))
            }
            .task(id: tear.isActive) {
                // While the finger pauses no progress arrives: fade the sound.
                guard tear.isActive else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(90))
                    if (ContinuousClock.Instant.now - lastTime).seconds > 0.12 {
                        sounds.tearing(speed: 0)
                    }
                }
            }
    }
}
