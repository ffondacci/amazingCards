import CardCore
import SwiftUI

/// Circular energy icon of a creature element.
public struct ElementIcon: View {
    public var element: CreatureElement
    public var diameter: CGFloat

    public init(_ element: CreatureElement, diameter: CGFloat) {
        self.element = element
        self.diameter = diameter
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(element.color).opacity(0.95), Color(element.color).opacity(0.7)],
                        center: .topLeading, startRadius: 0, endRadius: diameter
                    )
                )
            Circle().strokeBorder(.white.opacity(0.9), lineWidth: diameter * 0.07)
            Image(systemName: element.symbolName)
                .font(.system(size: diameter * 0.52, weight: .bold))
                .foregroundStyle(Color(element.color.contrastingText))
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.25), radius: diameter * 0.08, y: diameter * 0.05)
        .accessibilityLabel(element.displayName)
    }
}

/// Rarity glyph with its tier colour.
public struct RaritySymbol: View {
    public var rarity: Rarity
    public var size: CGFloat

    public init(_ rarity: Rarity, size: CGFloat) {
        self.rarity = rarity
        self.size = size
    }

    public var body: some View {
        Image(systemName: rarity.symbolName)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Color(rarity.color))
            .shadow(color: .black.opacity(0.3), radius: size * 0.1)
            .accessibilityLabel(rarity.displayName)
    }
}

/// Small rounded label (stage, kind, movement…).
public struct CardPill: View {
    public var text: String
    public var font: Font
    public var fill: Color
    public var foreground: Color
    public var paddingX: CGFloat

    public init(_ text: String, font: Font, fill: Color, foreground: Color, paddingX: CGFloat) {
        self.text = text
        self.font = font
        self.fill = fill
        self.foreground = foreground
        self.paddingX = paddingX
    }

    public var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(foreground)
            .padding(.horizontal, paddingX)
            .padding(.vertical, paddingX * 0.35)
            .background(Capsule().fill(fill))
    }
}

/// Slanted silver strip used under the artwork of creature cards.
public struct SlantedStrip: Shape {
    public var slant: CGFloat

    public init(slant: CGFloat = 0.6) { self.slant = slant }

    public func path(in rect: CGRect) -> Path {
        let dx = rect.height * slant
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + dx, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - dx, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
