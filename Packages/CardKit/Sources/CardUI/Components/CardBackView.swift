import CardCore
import CardFX
import SwiftUI

/// Procedural back of a card: gradient, animated nebula, emblem, border.
/// Driven by `CardTheme.back` unless a design is passed explicitly.
public struct CardBackView: View {
    public var design: CardBackDesign?
    @Environment(\.cardTheme) private var theme

    public init(design: CardBackDesign? = nil) {
        self.design = design
    }

    public var body: some View {
        let back = design ?? theme.back
        GeometryReader { proxy in
            let m = CardMetrics(size: proxy.size, cornerRadiusPercent: theme.cornerRadiusPercent)
            ZStack {
                LinearGradient(
                    colors: back.colors.map(Color.init),
                    startPoint: .top, endPoint: .bottom
                )
                Rectangle()
                    .fill(.black)
                    .cardEffect(.nebula(palette: back.nebulaPalette, intensity: 0.9))
                    .blendMode(.screen)
                    .opacity(0.9)
                m.innerShape
                    .strokeBorder(Color(back.borderColor).opacity(0.9), lineWidth: m.pt(0.7))
                    .padding(m.pt(3.5))
                m.innerShape
                    .strokeBorder(Color(back.borderColor).opacity(0.45), lineWidth: m.pt(0.3))
                    .padding(m.pt(5.5))
                VStack(spacing: m.ptH(2)) {
                    Image(systemName: back.emblemSymbol)
                        .font(.system(size: m.pt(26), weight: .regular))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(back.borderColor), .white],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .shadow(color: Color(back.borderColor).opacity(0.8), radius: m.pt(3))
                    Text(back.title)
                        .font(m.font(4.6, weight: .heavy, design: .rounded))
                        .tracking(m.pt(1))
                        .foregroundStyle(Color(back.borderColor))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(m.shape)
            .overlay { m.shape.strokeBorder(.white.opacity(0.18), lineWidth: max(m.pt(0.35), 0.5)) }
        }
        .aspectRatio(CardMetrics.aspectRatio, contentMode: .fit)
        .accessibilityLabel("Card back")
    }
}
