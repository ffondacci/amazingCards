import CardCore
import CardFX
import SwiftUI

/// Classic framed trading card: name bar, artwork window, attacks, footer.
/// Proportions follow the 733 × 1024 reference layout.
struct CreatureCardFace: View {
    let card: Card
    let creature: Creature
    let metrics: CardMetrics
    let recipe: FinishRecipe
    @Environment(\.cardTheme) private var theme

    private var accent: Color { Color(creature.element.color) }
    private var m: CardMetrics { metrics }
    private var titleDesign: Font.Design { theme.titleDesign ?? .rounded }

    var body: some View {
        ZStack {
            frame
            VStack(spacing: 0) {
                header
                    .frame(height: m.ptH(6.5))
                    .padding(.horizontal, m.pt(1))
                artworkWindow
                    .frame(height: m.ptH(37.4))
                speciesStrip
                    .frame(height: m.ptH(2.8))
                    .padding(.top, m.ptH(0.4))
                attacks
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, m.ptH(1.2))
                statsRow
                    .frame(height: m.ptH(3.4))
                footer
                    .frame(height: m.ptH(8))
                    .padding(.top, m.ptH(0.6))
            }
            .padding(.horizontal, m.pt(7.8))
            .padding(.top, m.ptH(3.4))
            .padding(.bottom, m.ptH(1.2))
        }
    }

    // MARK: Frame

    private var frame: some View {
        ZStack {
            // Border: warm yellow, like the classic print.
            m.shape.fill(
                LinearGradient(
                    colors: theme.creatureFrame.map(Color.init),
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            // Inner paper tinted by the element.
            Rectangle()
                .fill(.black)
                .cardMotionIdle(animates: false)
                .cardEffect(.holoPaper(hue: creature.element.color.hue, intensity: theme.paperIntensity))
                .clipShape(m.innerShape)
                .padding(m.borderWidth)
                .cardEffects(recipe.frame)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: m.pt(2)) {
            CardPill(
                creature.stage.uppercased(),
                font: m.font(2.6, weight: .heavy, design: .rounded),
                fill: .black.opacity(0.85),
                foreground: .white,
                paddingX: m.pt(1.6)
            )
            Text(card.title)
                .font(m.font(7, weight: .heavy, design: titleDesign))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: m.pt(0.6)) {
                Text("HP")
                    .font(m.font(2.4, weight: .bold, design: .rounded))
                Text("\(creature.hitPoints)")
                    .font(m.font(6.5, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.black)
            ElementIcon(creature.element, diameter: m.pt(6.4))
        }
    }

    // MARK: Artwork

    private var artworkWindow: some View {
        // Explicit frame: a flexible frame would grow to the image size and
        // defeat the clip (its lower bound defaults to the child size).
        let window = CGSize(width: m.width - 2 * m.pt(7.8), height: m.ptH(37.4))
        return ArtworkView(card.artwork, contentMode: .fill)
            .frame(width: window.width, height: window.height)
            .clipped()
            .cardEffects(recipe.artwork)
            .overlay {
            Rectangle().strokeBorder(
                LinearGradient(
                    colors: [Color(white: 0.95), Color(white: 0.55), Color(white: 0.9)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: m.pt(0.9)
            )
            }
            .shadow(color: .black.opacity(0.35), radius: m.pt(0.8), y: m.pt(0.4))
    }

    private var speciesStrip: some View {
        Text(creature.species)
            .font(m.font(2.4, weight: .medium, design: .rounded).italic())
            .foregroundStyle(.black.opacity(0.8))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, m.pt(6))
            .frame(maxWidth: .infinity)
            .background {
                SlantedStrip(slant: 0.9)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.98), Color(white: 0.78), Color(white: 0.96)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, m.pt(3))
            }
    }

    // MARK: Attacks

    private var attacks: some View {
        VStack(spacing: m.ptH(1.2)) {
            ForEach(Array(creature.attacks.enumerated()), id: \.offset) { _, attack in
                AttackRow(attack: attack, metrics: m)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: m.pt(1.5)) {
            statBox(label: "weakness") {
                if let weakness = creature.weakness {
                    ElementIcon(weakness, diameter: m.pt(3.2))
                    Text("×2").font(m.font(3, weight: .heavy, design: .rounded))
                }
            }
            statBox(label: "resistance") {
                if let resistance = creature.resistance {
                    ElementIcon(resistance, diameter: m.pt(3.2))
                    Text("−30").font(m.font(3, weight: .heavy, design: .rounded))
                }
            }
            statBox(label: "retreat") {
                HStack(spacing: m.pt(0.3)) {
                    ForEach(0..<max(creature.retreatCost, 0), id: \.self) { _ in
                        ElementIcon(.colorless, diameter: m.pt(3.2))
                    }
                }
            }
        }
        .foregroundStyle(.black)
    }

    private func statBox(label: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(spacing: m.pt(1)) {
            Text(label)
                .font(m.font(2.2, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.75))
            value()
        }
        .padding(.horizontal, m.pt(2))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            SlantedStrip(slant: 0.7).fill(Color.white.opacity(0.85))
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .bottom, spacing: m.pt(2)) {
            VStack(alignment: .leading, spacing: m.ptH(0.3)) {
                if let credit = card.credit {
                    Text("Illus. \(credit)")
                        .font(m.font(2.2, weight: .medium).italic())
                }
                HStack(spacing: m.pt(0.8)) {
                    if let number = card.number {
                        Text(number.formatted).font(m.font(2.4, weight: .bold, design: .rounded))
                    }
                    RaritySymbol(card.rarity, size: m.pt(2.4))
                }
                if let setName = card.setName {
                    Text(setName)
                        .font(m.font(1.9, weight: .regular))
                        .foregroundStyle(.black.opacity(0.6))
                }
            }
            .foregroundStyle(.black.opacity(0.85))
            Spacer(minLength: 0)
            if let flavor = creature.flavorText {
                Text(flavor)
                    .font(m.font(2.1).italic())
                    .foregroundStyle(.black.opacity(0.8))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: m.pt(50), alignment: .trailing)
            }
        }
    }
}

/// Energy cost, name, damage, rule text.
struct AttackRow: View {
    let attack: Attack
    let metrics: CardMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.ptH(0.3)) {
            HStack(spacing: metrics.pt(1.5)) {
                HStack(spacing: metrics.pt(0.4)) {
                    ForEach(Array(attack.cost.enumerated()), id: \.offset) { _, element in
                        ElementIcon(element, diameter: metrics.pt(5))
                    }
                }
                .frame(minWidth: metrics.pt(16), alignment: .leading)
                Text(attack.name)
                    .font(metrics.font(5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                if let damage = attack.damage {
                    Text("\(damage)")
                        .font(metrics.font(6, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(minWidth: metrics.pt(10), alignment: .trailing)
                }
            }
            if let text = attack.text {
                Text(text)
                    .font(metrics.font(2.6))
                    .foregroundStyle(.black.opacity(0.9))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(CardColor(hex: hex))
    }
}
