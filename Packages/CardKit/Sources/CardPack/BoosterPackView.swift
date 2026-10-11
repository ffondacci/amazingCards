import CardCore
import CardFX
import CardUI
import SwiftUI

/// Printed wrapper of a booster in the pocket-pack style: a tall pouch with
/// crimped ends, a thick top band with the brand and the set code over a
/// double seam, a full-bleed cover with a foil sheen, the big set name and a
/// name plate just above a thin bottom band. Purely visual; `PackOpeningView`
/// adds the gesture.
public struct BoosterPackView: View {
    public var design: PackDesign

    public init(design: PackDesign) {
        self.design = design
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let top = h * design.stripFraction
            let bottom = h * design.bottomFraction
            let seal = h * 0.028
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

                // Seam: a bright double line where the top band is sealed.
                VStack(spacing: max(w * 0.006, 1)) {
                    Rectangle()
                        .fill(Color(design.accent))
                        .frame(width: w, height: max(w * 0.008, 1.5))
                        .shadow(color: Color(design.accent).opacity(0.9), radius: w * 0.012)
                    Rectangle()
                        .fill(.white.opacity(0.85))
                        .frame(width: w, height: max(w * 0.004, 1))
                }
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
                .padding(.top, h - bottom - h * 0.19)

                // Crimped seals pressed into both ends of the pouch.
                VStack(spacing: 0) {
                    SealBand(color: Color(design.topColor)).frame(width: w, height: seal)
                    Spacer(minLength: 0)
                    SealBand(color: Color(design.bottomColor)).frame(width: w, height: seal).rotationEffect(.degrees(180))
                }
            }
            .frame(width: w, height: h)
            .cardEffect(.holo(.prism, intensity: design.prismIntensity), isEnabled: design.prismIntensity > 0.005)
            .clipShape(PackShape())
            .overlay {
                PackShape()
                    .stroke(.white.opacity(0.25), lineWidth: max(w * 0.004, 0.8))
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
            // Brand block centred like a logo, the set code in the corner.
            VStack(spacing: height * 0.02) {
                HStack(alignment: .center, spacing: w * 0.025) {
                    Image(systemName: design.emblemSymbol)
                        .font(.system(size: height * 0.3, weight: .bold))
                        .foregroundStyle(Color(design.accent))
                        .shadow(color: Color(design.accent).opacity(0.8), radius: height * 0.08)
                    Text(design.brand)
                        .font(.system(size: height * 0.21, weight: .black, design: .rounded))
                        .tracking(height * 0.02)
                }
                Text("\(design.cardCount) CARDS")
                    .font(.system(size: height * 0.12, weight: .bold, design: .rounded))
                    .tracking(height * 0.03)
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, w * 0.2)
            .padding(.top, height * 0.16)
            .shadow(color: .black.opacity(0.35), radius: height * 0.03, y: height * 0.02)
        }
        .frame(width: w, height: height)
        .overlay(alignment: .topTrailing) {
            if let setCode = design.setCode {
                Text(setCode)
                    .font(.system(size: height * 0.17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, height * 0.12)
                    .padding(.vertical, height * 0.05)
                    .background(RoundedRectangle(cornerRadius: height * 0.08).fill(.black.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: height * 0.08).stroke(.white.opacity(0.5), lineWidth: 1))
                    .padding(.top, height * 0.24)
                    .padding(.trailing, w * 0.04)
            }
        }
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
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Silhouette of a sealed pouch: flat crimped ends, long sides bowing out a
/// little where the cards push, small rounded corners.
public struct PackShape: Shape {
    /// How far each long side bows out, as a fraction of the width.
    public var bow: CGFloat
    /// Corner radius as a fraction of the width.
    public var corner: CGFloat

    public init(bow: CGFloat = 0.014, corner: CGFloat = 0.03) {
        self.bow = bow
        self.corner = corner
    }

    public func path(in rect: CGRect) -> Path {
        let inset = rect.width * bow
        let r = rect.width * corner
        let left = rect.minX + inset
        let right = rect.maxX - inset
        var path = Path()
        path.move(to: CGPoint(x: left + r, y: rect.minY))
        path.addLine(to: CGPoint(x: right - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + r), control: CGPoint(x: right, y: rect.minY))
        // A quadratic curve peaks halfway to its control point, so a control
        // at `inset` beyond the edge brings the side exactly to the bounds.
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - r), control: CGPoint(x: rect.maxX + inset, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: right - r, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: left + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - r), control: CGPoint(x: left, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + r), control: CGPoint(x: rect.minX - inset, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: left + r, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Crimped seal of a pouch end: a lighter strip pressed with fine vertical
/// ridges, its inner edge cut in a sawtooth. Rotate it for the bottom.
struct SealBand: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            let base = Path(CGRect(origin: .zero, size: size))
            context.fill(base, with: .color(color))
            context.fill(base, with: .color(.white.opacity(0.18)))
            // Ridges: alternating light and dark hairlines.
            let step = max(size.width * 0.018, 2)
            var x: CGFloat = step / 2
            var dark = false
            while x < size.width {
                let line = Path(CGRect(x: x, y: 0, width: max(step * 0.3, 0.6), height: size.height))
                context.fill(line, with: .color(dark ? .black.opacity(0.28) : .white.opacity(0.22)))
                x += step
                dark.toggle()
            }
            // Shadow along the sawtooth edge.
            let teeth = max(Int(size.width / (step * 2)), 8)
            var edge = CrimpBand(teeth: teeth).path(in: CGRect(origin: .zero, size: size))
            edge = edge.applying(CGAffineTransform(translationX: 0, y: size.height * 0.3))
            context.fill(edge, with: .color(.black.opacity(0.22)))
        }
        .mask(CrimpBand(teeth: 40))
        .allowsHitTesting(false)
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
