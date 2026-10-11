import CardCore
import CardUI
import SwiftUI

/// Back of a sealed pack, as printed: the two bands, a pale body with the
/// contents in columns of fine print, the brand and a barcode. Drawn from
/// the same `PackDesign` as the front, sized relative to its width.
public struct PackBackView: View {
    public var design: PackDesign
    /// Draw the foil mask instead of the print.
    public var asMask: Bool

    public init(design: PackDesign, asMask: Bool = false) {
        self.design = design
        self.asMask = asMask
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let top = h * design.stripFraction
            let bottom = h * design.bottomFraction
            let foil = PackPrintKind.maskColor(foil: 1, holo: 1, matte: 0)
            let chrome = PackPrintKind.maskColor(foil: 1, holo: 0.35, matte: 0)
            let body = PackPrintKind.maskColor(foil: 0.55, holo: 0.08, matte: 0.15)
            let ink = PackPrintKind.maskColor(foil: 0.1, holo: 0, matte: 0.5)
            ZStack(alignment: .top) {
                if asMask {
                    body
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.93), Color(white: 0.86), Color(white: 0.9)],
                        startPoint: .top, endPoint: .bottom
                    )
                    EmblemPattern(symbol: design.emblemSymbol, spacing: w * 0.16)
                        .foregroundStyle(Color(design.topColor).opacity(0.08))
                }
                VStack(spacing: 0) {
                    ZStack {
                        asMask ? foil : Color(design.topColor)
                        HStack {
                            Image(systemName: design.emblemSymbol)
                                .font(.system(size: top * 0.3, weight: .bold))
                                .foregroundStyle(asMask ? chrome : Color(design.accent))
                            Text(design.brand)
                                .font(.system(size: top * 0.2, weight: .black, design: .rounded))
                                .foregroundStyle(asMask ? chrome : .white)
                        }
                    }
                    .frame(height: top)
                    Spacer(minLength: 0)
                    (asMask ? foil : Color(design.bottomColor)).frame(height: bottom)
                }
                VStack(alignment: .leading, spacing: h * 0.02) {
                    Text("CONTAINS \(design.cardCount) CARDS")
                        .font(.system(size: w * 0.045, weight: .heavy, design: .rounded))
                        .tracking(w * 0.004)
                    Text(design.title.uppercased())
                        .font(.system(size: w * 0.06, weight: .black, design: .rounded))
                    fineLines(width: w * 0.82, lines: 9, seed: 3)
                    fineLines(width: w * 0.6, lines: 5, seed: 7)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom) {
                        Barcode(bars: 44)
                            .fill(.black.opacity(0.85))
                            .frame(width: w * 0.42, height: w * 0.14)
                        Spacer()
                        Text("6+")
                            .font(.system(size: w * 0.05, weight: .bold, design: .rounded))
                            .padding(w * 0.02)
                            .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: w * 0.006))
                    }
                }
                .foregroundStyle(asMask ? ink : .black.opacity(0.72))
                .padding(.horizontal, w * 0.09)
                .padding(.top, top + h * 0.05)
                .padding(.bottom, bottom + h * 0.04)
                .frame(width: w, height: h, alignment: .top)
            }
        }
        .aspectRatio(PackDesign.aspectRatio, contentMode: .fit)
    }

    /// Rows of grey "text" of varying length.
    private func fineLines(width: CGFloat, lines: Int, seed: Int) -> some View {
        VStack(alignment: .leading, spacing: width * 0.025) {
            ForEach(0..<lines, id: \.self) { i in
                let f = 0.55 + 0.45 * abs(sin(Double(i * 7 + seed) * 1.7))
                Capsule()
                    .fill(.black.opacity(0.35))
                    .frame(width: width * f, height: width * 0.018)
            }
        }
    }
}

/// Barcode: bars of pseudo-random widths.
public struct Barcode: Shape {
    public var bars: Int

    public init(bars: Int = 40) { self.bars = bars }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let unit = rect.width / CGFloat(bars * 3)
        var x = rect.minX
        for i in 0..<bars {
            let width = unit * (1 + CGFloat((i * 7919 + 13) % 3))
            let gap = unit * (1 + CGFloat((i * 104729 + 5) % 2))
            path.addRect(CGRect(x: x, y: rect.minY, width: width, height: rect.height))
            x += width + gap
            if x > rect.maxX { break }
        }
        return path
    }
}
