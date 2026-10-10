import CardCore
import CardFX
import SwiftUI

/// Dark borderless card for a celestial object: photo at the top fading into
/// a procedural star field, designation, kind badge and a data grid.
struct CelestialCardFace: View {
    let card: Card
    let object: CelestialObject
    let metrics: CardMetrics
    let recipe: FinishRecipe
    @Environment(\.cardTheme) private var theme

    private var m: CardMetrics { metrics }
    private var accent: CardColor { card.resolvedAccent }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.black)
                .cardEffect(.starfield(density: 34, intensity: 1))
            VStack(spacing: 0) {
                photo
                    .frame(height: m.ptH(56))
                info
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .cardEffects(recipe.artwork)
        }
        .overlay {
            m.shape
                .strokeBorder(Color(accent).opacity(0.6), lineWidth: m.pt(0.35))
                .padding(m.pt(2))
        }
    }

    private var photo: some View {
        ZStack(alignment: .bottom) {
            ArtworkView(card.artwork, contentMode: .fill)
                .frame(width: m.width, height: m.ptH(56))
                .clipped()
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: m.ptH(18))
        }
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: m.ptH(1)) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title.uppercased())
                    .font(m.font(6.6, weight: .bold, design: theme.titleDesign ?? .rounded))
                    .tracking(m.pt(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer()
                Image(systemName: object.kind.symbolName)
                    .font(m.font(4.5, weight: .semibold))
                    .foregroundStyle(Color(accent))
            }
            Text(object.designation)
                .font(m.font(3, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(accent))
            HStack(spacing: m.pt(1.5)) {
                CardPill(
                    object.kind.displayName.uppercased(),
                    font: m.font(2.2, weight: .heavy, design: .rounded),
                    fill: Color(accent).opacity(0.22),
                    foreground: Color(accent),
                    paddingX: m.pt(1.6)
                )
                CardPill(
                    object.constellation.uppercased(),
                    font: m.font(2.2, weight: .heavy, design: .rounded),
                    fill: .white.opacity(0.12),
                    foreground: .white.opacity(0.85),
                    paddingX: m.pt(1.6)
                )
            }
            dataGrid
                .padding(.top, m.ptH(0.5))
            Text(object.description)
                .font(m.font(2.6))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(4)
                .minimumScaleFactor(0.7)
                .padding(.top, m.ptH(0.5))
            Spacer(minLength: 0)
            HStack {
                if let credit = card.credit {
                    Text(credit).font(m.font(2)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                HStack(spacing: m.pt(0.8)) {
                    if let number = card.number {
                        Text(number.formatted).font(m.font(2.4, weight: .bold, design: .monospaced))
                    }
                    RaritySymbol(card.rarity, size: m.pt(2.4))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, m.pt(6))
        .padding(.top, m.ptH(0.5))
        .padding(.bottom, m.ptH(3.5))
    }

    private var dataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: m.pt(3), verticalSpacing: m.ptH(0.5)) {
            GridRow {
                dataCell("Distance", object.distance)
                if let magnitude = object.apparentMagnitude {
                    dataCell("Magnitude", String(format: "%.1f", magnitude))
                }
            }
            GridRow {
                if let size = object.apparentSize {
                    dataCell("Size", size)
                }
                dataCell("Constellation", object.constellation)
            }
        }
    }

    private func dataCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(m.font(1.9, weight: .semibold))
                .tracking(m.pt(0.2))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(m.font(2.9, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
