import CardCore
import CardFX
import CardUI
import SwiftUI

/// Printed wrapper of a booster in the pocket-pack style: top band with the
/// brand and set code, bright seam, full-bleed cover with a foil sheen, big
/// set name and a name plate over the bottom band. Purely visual;
/// `PackOpeningView` adds the gesture.
public struct BoosterPackView: View {
    public var design: PackDesign
    /// How much the cards inside push the wrapper out, 0…1.
    public var bulge: Double
    /// Strength of the paper shading (folds, wrinkles, crimps); 0 = flat print.
    public var paperIntensity: Double

    public init(design: PackDesign, bulge: Double = 1, paperIntensity: Double = 1) {
        self.design = design
        self.bulge = bulge
        self.paperIntensity = paperIntensity
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let top = h * design.stripFraction
            let bottom = h * design.bottomFraction
            let radius = w * 0.035
            ZStack(alignment: .top) {
                // Full-bleed cover with a metallic sheen.
                ArtworkView(design.cover, contentMode: .fill)
                    .frame(width: w, height: h)
                    .clipped()
                    .cardEffect(.foilWrap(hue: design.foilHue, intensity: 0.18))
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.22), location: 0),
                                .init(color: .clear, location: 0.35),
                                .init(color: .clear, location: 0.7),
                                .init(color: .black.opacity(0.25), location: 1),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }

                // Bands.
                VStack(spacing: 0) {
                    topBand(width: w, height: top)
                    Spacer(minLength: 0)
                    bottomBand(width: w, height: bottom)
                }

                // Seam: bright line where the top band is sealed.
                Rectangle()
                    .fill(Color(design.accent))
                    .frame(width: w, height: max(w * 0.008, 1.5))
                    .shadow(color: Color(design.accent).opacity(0.9), radius: w * 0.012)
                    .offset(y: top)

                // Set name and plate over the bottom of the cover.
                VStack(spacing: h * 0.008) {
                    Text(design.title.uppercased())
                        .font(.system(size: w * 0.12, weight: .black, design: .rounded))
                        .tracking(w * 0.004)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(
                            LinearGradient(colors: [.white, Color(design.accent).opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: .black.opacity(0.7), radius: w * 0.012, y: w * 0.008)
                        .shadow(color: Color(design.accent).opacity(0.5), radius: w * 0.03)
                    if let subtitle = design.subtitle {
                        Text(subtitle)
                            .font(.system(size: w * 0.055, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, w * 0.06)
                            .padding(.vertical, w * 0.012)
                            .background {
                                NamePlate()
                                    .fill(Color(design.accent))
                                    .overlay { NamePlate().stroke(.white.opacity(0.7), lineWidth: max(w * 0.004, 1)) }
                                    .shadow(color: .black.opacity(0.5), radius: w * 0.01, y: w * 0.006)
                            }
                    }
                }
                .frame(width: w)
                .padding(.top, h - bottom - h * 0.165)

                // Sealed edges: tiny crimps at the very top and bottom.
                VStack {
                    CrimpBand(teeth: 30).fill(.black.opacity(0.35)).frame(height: h * 0.014)
                    Spacer()
                    CrimpBand(teeth: 30).fill(.black.opacity(0.35)).frame(height: h * 0.014).rotationEffect(.degrees(180))
                }
            }
            .frame(width: w, height: h)
            .cardEffect(.holo(.prism, intensity: design.prismIntensity), isEnabled: design.prismIntensity > 0.005)
            .cardEffect(.paper(bulge: bulge, crimp: h * 0.014, intensity: paperIntensity), isEnabled: paperIntensity > 0.01)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: max(w * 0.004, 0.8))
            }
        }
        .aspectRatio(PackDesign.aspectRatio, contentMode: .fit)
    }

    private func topBand(width w: CGFloat, height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(design.topColor).opacity(0.95), Color(design.topColor)],
                startPoint: .top, endPoint: .bottom
            )
            EmblemPattern(symbol: design.emblemSymbol, spacing: w * 0.16)
                .foregroundStyle(.white.opacity(0.08))
            HStack(alignment: .center, spacing: w * 0.03) {
                Image(systemName: design.emblemSymbol)
                    .font(.system(size: height * 0.42, weight: .bold))
                    .foregroundStyle(Color(design.accent))
                    .shadow(color: Color(design.accent).opacity(0.8), radius: height * 0.1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(design.brand)
                        .font(.system(size: height * 0.26, weight: .black, design: .rounded))
                        .tracking(height * 0.02)
                    Text("\(design.cardCount) CARDS")
                        .font(.system(size: height * 0.18, weight: .bold, design: .rounded))
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if let setCode = design.setCode {
                    Text(setCode)
                        .font(.system(size: height * 0.24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, height * 0.16)
                        .padding(.vertical, height * 0.07)
                        .background(RoundedRectangle(cornerRadius: height * 0.12).fill(.black.opacity(0.55)))
                        .overlay(RoundedRectangle(cornerRadius: height * 0.12).stroke(.white.opacity(0.5), lineWidth: 1))
                }
            }
            .padding(.horizontal, w * 0.06)
        }
        .frame(width: w, height: height)
    }

    private func bottomBand(width w: CGFloat, height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(design.bottomColor), Color(design.bottomColor).opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
            EmblemPattern(symbol: design.emblemSymbol, spacing: w * 0.16)
                .foregroundStyle(.white.opacity(0.06))
        }
        .frame(width: w, height: height)
        .mask {
            // Soft top edge so the band blends into the cover.
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.35)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Faint repeated emblem, like the ball pattern of real wrappers.
struct EmblemPattern: View {
    var symbol: String
    var spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            let columns = Int(size.width / spacing) + 2
            let rows = Int(size.height / spacing) + 2
            let glyph = context.resolve(Text(Image(systemName: symbol)).font(.system(size: spacing * 0.45)))
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = CGFloat(column) * spacing + (row.isMultiple(of: 2) ? 0 : spacing / 2) - spacing / 2
                    let y = CGFloat(row) * spacing - spacing / 2
                    context.draw(glyph, at: CGPoint(x: x, y: y))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Hexagonal plate holding the pack name.
public struct NamePlate: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let cut = rect.height * 0.5
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
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
