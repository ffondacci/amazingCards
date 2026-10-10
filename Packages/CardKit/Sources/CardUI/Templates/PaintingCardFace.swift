import CardCore
import CardFX
import SwiftUI

/// Borderless painting card: the artwork bleeds to the edges, a caption strip
/// fades in from the bottom.
struct PaintingCardFace: View {
    let card: Card
    let painting: Painting
    let metrics: CardMetrics
    let recipe: FinishRecipe
    @Environment(\.cardTheme) private var theme

    private var m: CardMetrics { metrics }

    var body: some View {
        ZStack(alignment: .bottom) {
            ArtworkView(card.artwork, contentMode: .fill)
                .frame(width: m.width, height: m.height)
                .clipped()
                .cardEffects(recipe.artwork)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.55), location: 0.45),
                    .init(color: .black.opacity(0.92), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: m.ptH(42))
            caption
            topRight
        }
        .overlay {
            m.shape
                .strokeBorder(.white.opacity(0.35), lineWidth: m.pt(0.35))
                .padding(m.pt(2))
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: m.ptH(0.6)) {
            Text(card.title)
                .font(m.font(7, weight: .semibold, design: theme.titleDesign ?? .serif))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text("\(painting.artist)  ·  \(painting.year)")
                .font(m.font(3.2, weight: .medium, design: .serif))
                .opacity(0.9)
            Text(painting.medium + (painting.dimensions.map { "  ·  \($0)" } ?? ""))
                .font(m.font(2.5, design: .serif))
                .opacity(0.7)
            if let location = painting.location {
                HStack(spacing: m.pt(1)) {
                    Image(systemName: "building.columns.fill").font(m.font(2.2))
                    Text(location).font(m.font(2.5, design: .serif))
                }
                .opacity(0.7)
            }
            Text(painting.description)
                .font(m.font(2.6, design: .serif))
                .opacity(0.85)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .padding(.top, m.ptH(0.5))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, m.pt(6))
        .padding(.bottom, m.ptH(4))
    }

    private var topRight: some View {
        VStack {
            HStack(alignment: .top) {
                if let setName = card.setName {
                    Text(setName.uppercased())
                        .font(m.font(2.2, weight: .semibold))
                        .tracking(m.pt(0.3))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, m.pt(2))
                        .padding(.vertical, m.pt(0.8))
                        .background(Capsule().fill(.black.opacity(0.35)))
                }
                Spacer()
                HStack(spacing: m.pt(0.8)) {
                    if let number = card.number {
                        Text(number.formatted).font(m.font(2.4, weight: .bold, design: .rounded))
                    }
                    RaritySymbol(card.rarity, size: m.pt(2.6))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, m.pt(2))
                .padding(.vertical, m.pt(0.8))
                .background(Capsule().fill(.black.opacity(0.35)))
            }
            Spacer()
        }
        .padding(m.pt(5))
    }
}
