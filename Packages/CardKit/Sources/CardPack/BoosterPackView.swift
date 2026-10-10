import CardCore
import CardFX
import CardUI
import SwiftUI

/// Printed wrapper of a booster: crimped bands, foil texture, cover window,
/// title and emblem. Purely visual; `PackOpeningView` adds the gesture.
public struct BoosterPackView: View {
    public var design: PackDesign

    public init(design: PackDesign) {
        self.design = design
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let band = h * 0.065
            ZStack {
                // Wrapper base + foil.
                RoundedRectangle(cornerRadius: w * 0.03, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: design.baseColors.map(Color.init),
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .cardEffect(.foilWrap(hue: design.foilHue, intensity: 0.85))
                // Crimped bands.
                VStack {
                    CrimpBand(teeth: 26).fill(Color(design.bandColor).opacity(0.85)).frame(height: band)
                    Spacer()
                    CrimpBand(teeth: 26).fill(Color(design.bandColor).opacity(0.85)).frame(height: band).rotationEffect(.degrees(180))
                }
                // Perforation line of the tear strip.
                Path { path in
                    path.move(to: CGPoint(x: w * 0.04, y: h * design.stripFraction))
                    path.addLine(to: CGPoint(x: w * 0.96, y: h * design.stripFraction))
                }
                .stroke(style: StrokeStyle(lineWidth: max(w * 0.004, 0.8), dash: [w * 0.02, w * 0.015]))
                .foregroundStyle(.white.opacity(0.45))
                // Content.
                VStack(spacing: h * 0.02) {
                    Spacer(minLength: h * design.stripFraction + h * 0.02)
                    Text(design.title.uppercased())
                        .font(.system(size: w * 0.11, weight: .black, design: .rounded))
                        .tracking(w * 0.01)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: w * 0.01, y: w * 0.005)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let subtitle = design.subtitle {
                        Text(subtitle)
                            .font(.system(size: w * 0.045, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    ArtworkView(design.cover, contentMode: .fill)
                        .frame(width: w * 0.74, height: h * 0.42)
                        .clipShape(RoundedRectangle(cornerRadius: w * 0.04, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: w * 0.04, style: .continuous)
                                .strokeBorder(.white.opacity(0.6), lineWidth: w * 0.01)
                        }
                        .shadow(color: .black.opacity(0.45), radius: w * 0.03, y: w * 0.02)
                    HStack(spacing: w * 0.03) {
                        Image(systemName: design.emblemSymbol)
                            .font(.system(size: w * 0.07, weight: .bold))
                        Text("\(design.cardCount) CARDS")
                            .font(.system(size: w * 0.05, weight: .heavy, design: .rounded))
                            .tracking(w * 0.006)
                    }
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, w * 0.05)
                    .padding(.vertical, w * 0.02)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    Spacer(minLength: band + h * 0.02)
                }
                .padding(.horizontal, w * 0.06)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: w * 0.03, style: .continuous))
        }
        .aspectRatio(PackDesign.aspectRatio, contentMode: .fit)
    }
}

/// Zig-zag crimp drawn at the top of a pack (rotate for the bottom).
public struct CrimpBand: Shape {
    public var teeth: Int

    public init(teeth: Int = 24) { self.teeth = teeth }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / CGFloat(max(teeth, 1))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.55))
        for i in stride(from: teeth, through: 0, by: -1) {
            let x = rect.minX + step * CGFloat(i)
            let y = i % 2 == 0 ? rect.maxY : rect.maxY * 0.55
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }
}
