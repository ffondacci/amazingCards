import CardCore
import CardFX
import SwiftUI

/// Framed portrait card for an artist: sticker-style portrait on holo paper,
/// name banner, lifespan, movement, biography and notable works.
struct ArtistCardFace: View {
    let card: Card
    let artist: Artist
    let metrics: CardMetrics
    let recipe: FinishRecipe
    @Environment(\.cardTheme) private var theme

    private var m: CardMetrics { metrics }
    private var accent: CardColor { card.resolvedAccent }

    var body: some View {
        ZStack {
            frame
            VStack(spacing: 0) {
                portrait
                    .frame(height: m.ptH(46))
                banner
                    .frame(height: m.ptH(10))
                    .padding(.top, -m.ptH(3))
                details
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, m.ptH(1.5))
                footer
                    .frame(height: m.ptH(5.5))
            }
            .padding(m.borderWidth + m.pt(1.2))
        }
    }

    private var frame: some View {
        ZStack {
            m.shape.fill(
                LinearGradient(
                    colors: [Color(accent), Color(accent).opacity(0.7), Color(accent)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            m.shape
                .strokeBorder(.white.opacity(0.35), lineWidth: m.pt(0.5))
                .padding(m.pt(1.2))
            Rectangle()
                .fill(.black)
                .cardEffect(.holoPaper(hue: accent.hue + 0.08, intensity: theme.paperIntensity * 0.85))
                .cardMotionIdle(animates: false)
                .clipShape(m.innerShape)
                .padding(m.borderWidth)
                .cardEffects(recipe.frame)
        }
    }

    private var portrait: some View {
        ZStack {
            RadialGradient(
                colors: [Color(accent).opacity(0.35), .clear],
                center: .center, startRadius: 0, endRadius: m.pt(40)
            )
            ArtworkView(card.artwork, contentMode: .fit)
                .padding(.horizontal, m.pt(3))
                .padding(.top, m.pt(2))
                .shadow(color: .black.opacity(0.3), radius: m.pt(1.2), y: m.pt(0.8))
        }
        .cardEffects(recipe.artwork)
    }

    private var banner: some View {
        VStack(spacing: m.ptH(0.2)) {
            Text(card.title)
                .font(m.font(7.4, weight: .bold, design: theme.titleDesign ?? .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("\(artist.lifespan)  ·  \(artist.nationality)")
                .font(m.font(2.8, weight: .medium, design: .serif))
                .opacity(0.8)
        }
        .foregroundStyle(Color(accent.contrastingText))
        .padding(.horizontal, m.pt(3))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: m.pt(2), style: .continuous)
                .fill(Color(accent))
                .shadow(color: .black.opacity(0.3), radius: m.pt(1), y: m.pt(0.5))
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: m.ptH(1)) {
            CardPill(
                artist.movement.uppercased(),
                font: m.font(2.4, weight: .heavy, design: .rounded),
                fill: Color(accent).opacity(0.18),
                foreground: Color(accent),
                paddingX: m.pt(1.8)
            )
            Text(artist.biography)
                .font(m.font(2.9, design: .serif))
                .foregroundStyle(.black.opacity(0.85))
                .lineLimit(6)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if !artist.notableWorks.isEmpty {
                VStack(alignment: .leading, spacing: m.ptH(0.3)) {
                    ForEach(artist.notableWorks.prefix(3), id: \.self) { work in
                        HStack(spacing: m.pt(1.2)) {
                            Image(systemName: "paintpalette.fill")
                                .font(m.font(2.2))
                                .foregroundStyle(Color(accent))
                            Text(work)
                                .font(m.font(2.7, weight: .semibold, design: .serif))
                                .foregroundStyle(.black.opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                }
            }
            if let quote = artist.quote {
                Text("“\(quote)”")
                    .font(m.font(2.6, design: .serif).italic())
                    .foregroundStyle(.black.opacity(0.65))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, m.ptH(0.5))
            }
        }
        .padding(.horizontal, m.pt(1.5))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            if let setName = card.setName {
                Text(setName.uppercased())
                    .font(m.font(2, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.55))
            }
            Spacer()
            HStack(spacing: m.pt(0.8)) {
                if let number = card.number {
                    Text(number.formatted).font(m.font(2.4, weight: .bold, design: .rounded))
                }
                RaritySymbol(card.rarity, size: m.pt(2.4))
            }
            .foregroundStyle(.black.opacity(0.8))
        }
        .padding(.horizontal, m.pt(1.5))
    }
}
