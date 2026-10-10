import CardCore
import CardFX
import CardUI
import SwiftUI

/// Every shader pass of `CardFX`, with a live preview and a playground.
struct EffectsCatalogView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Foil styles (ck_holo)") {
                    ForEach(CardEffect.showcase.filter(\.isHolo), id: \.self) { effect in
                        EffectRow(effect: effect)
                    }
                }
                Section("Overlays and generators") {
                    ForEach(CardEffect.showcase.filter { !$0.isHolo }, id: \.self) { effect in
                        EffectRow(effect: effect)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.06))
            .navigationTitle("Effects")
            .navigationDestination(for: CardEffect.self) { effect in
                EffectPlaygroundView(effect: effect)
            }
        }
    }
}

private struct EffectRow: View {
    let effect: CardEffect

    var body: some View {
        NavigationLink(value: effect) {
            HStack(spacing: 14) {
                EffectPreview(effect: effect, card: SampleLibrary.starryNight, intensity: 1, animates: false)
                    .frame(width: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(effect.displayName).font(.headline)
                    Text(effect.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if effect.isTimeDriven {
                    Image(systemName: "clock").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Applies one effect on a card (or on a plain surface for generators).
struct EffectPreview: View {
    let effect: CardEffect
    let card: Card
    let intensity: Double
    let animates: Bool

    var body: some View {
        Group {
            if effect.isGenerator {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(.black)
                        .cardEffect(effect.scaled(by: intensity))
                        .clipShape(RoundedRectangle(cornerRadius: proxy.size.width * 0.045, style: .continuous))
                }
                .aspectRatio(CardMetrics.aspectRatio, contentMode: .fit)
            } else {
                CardView(card: card, showsFinish: false)
                    .cardEffect(effect.scaled(by: intensity))
            }
        }
        .cardMotionIdle(animates: animates)
    }
}

/// Large interactive preview with an intensity slider and a subject picker.
struct EffectPlaygroundView: View {
    let effect: CardEffect
    @State private var intensity = 1.0
    @State private var subject: Card = SampleLibrary.starryNight
    @State private var progress = 0.0

    private var subjects: [Card] {
        [SampleLibrary.starryNight, SampleLibrary.vanGogh, SampleLibrary.andromeda, SampleLibrary.vincentCreature]
    }

    var body: some View {
        VStack(spacing: 18) {
            CardMotionStage(animates: effect.isTimeDriven || effect.isAnimatable) {
                Group {
                    if effect.isGenerator {
                        EffectPreview(effect: effect, card: subject, intensity: intensity, animates: true)
                    } else {
                        CardView(card: subject, showsFinish: false)
                            .modifier(AnimatableEffectHost(effect: effect, intensity: intensity, progress: progress))
                    }
                }
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 28)
            .frame(maxHeight: .infinity)

            VStack(spacing: 12) {
                if effect.isAnimatable {
                    Button {
                        progress = 0
                        withAnimation(.easeInOut(duration: 1.4)) { progress = 1 }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack {
                        Text("Intensity").font(.subheadline)
                        Slider(value: $intensity, in: 0...1)
                    }
                }
                if !effect.isGenerator {
                    Picker("Subject", selection: $subject) {
                        ForEach(subjects) { card in
                            Text(card.title).tag(card)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Text(effect.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .padding(.top, 8)
        .background(Color(white: 0.06).ignoresSafeArea())
        .navigationTitle(effect.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Hosts the effect; sweep and dissolve go through their animatable modifiers.
private struct AnimatableEffectHost: ViewModifier {
    let effect: CardEffect
    let intensity: Double
    let progress: Double

    func body(content: Content) -> some View {
        switch effect {
        case .sweep:
            content.cardSweep(progress: progress, intensity: 0.8)
        case .dissolve:
            content.cardDissolve(progress: progress > 0.5 ? (1 - progress) * 2 : progress * 2)
        default:
            content.cardEffect(effect.scaled(by: intensity))
        }
    }
}

extension CardEffect {
    var isHolo: Bool {
        if case .holo = self { return true }
        return false
    }

    /// Sweep and dissolve are driven by a progress animation, not a slider.
    var isAnimatable: Bool {
        switch self {
        case .sweep, .dissolve: true
        default: false
        }
    }

    /// Same effect with its main amount multiplied.
    func scaled(by factor: Double) -> CardEffect {
        switch self {
        case .holo(let style, let intensity): .holo(style, intensity: intensity * factor)
        case .glare(let intensity, let radius): .glare(intensity: intensity * factor, radius: radius)
        case .sparkle(let intensity, let density): .sparkle(intensity: intensity * factor, density: density)
        case .sweep: self
        case .shimmer(let intensity, let angle): .shimmer(intensity: intensity * factor, angle: angle)
        case .holoPaper(let hue, let intensity): .holoPaper(hue: hue, intensity: intensity * factor)
        case .foilWrap(let hue, let intensity): .foilWrap(hue: hue, intensity: intensity * factor)
        case .starfield(let density, let intensity): .starfield(density: density, intensity: intensity * factor)
        case .nebula(let palette, let intensity): .nebula(palette: palette, intensity: intensity * factor)
        case .burst(let tint, let intensity): .burst(tint: tint, intensity: intensity * factor)
        case .chromatic(let amount): .chromatic(amount: amount * factor * 2)
        case .dissolve: self
        }
    }
}
