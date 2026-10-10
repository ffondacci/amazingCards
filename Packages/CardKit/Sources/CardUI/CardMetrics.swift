import CardCore
import SwiftUI

/// Every dimension of a card expressed relative to its width, so the same
/// layout renders identically as a 90 pt thumbnail or a 600 pt hero card.
///
/// `pt(_:)` converts a percentage of the card width into points. Layout
/// numbers come from the 733 × 1024 reference design (ratio 0.716).
public struct CardMetrics: Hashable, Sendable {
    /// Standard playing-card ratio: 63 × 88 mm.
    public static let aspectRatio: CGFloat = 63.0 / 88.0

    public let size: CGSize
    /// Corner radius as a percentage of the width (4.5 % like a real card).
    public let cornerRadiusPercent: CGFloat

    public init(size: CGSize, cornerRadiusPercent: CGFloat = 4.5) {
        self.size = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        self.cornerRadiusPercent = cornerRadiusPercent
    }

    public init(width: CGFloat, cornerRadiusPercent: CGFloat = 4.5) {
        self.init(size: CGSize(width: width, height: width / Self.aspectRatio), cornerRadiusPercent: cornerRadiusPercent)
    }

    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }

    /// Points for a percentage of the card width.
    public func pt(_ percentOfWidth: CGFloat) -> CGFloat { size.width * percentOfWidth / 100 }

    /// Points for a percentage of the card height.
    public func ptH(_ percentOfHeight: CGFloat) -> CGFloat { size.height * percentOfHeight / 100 }

    /// Outer corner radius.
    public var cornerRadius: CGFloat { pt(cornerRadiusPercent) }

    /// Frame width of bordered templates (30 / 733 in the reference design).
    public var borderWidth: CGFloat { pt(4.1) }

    /// Rounded rectangle of the whole card.
    public var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Shape of the area inside the border.
    public var innerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: max(cornerRadius - borderWidth, pt(1)), style: .continuous)
    }

    /// Font scaled to the card.
    public func font(
        _ percentOfWidth: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: pt(percentOfWidth), weight: weight, design: design)
    }

    /// Frame of the artwork window on a framed card (reference design).
    public var artworkWindow: CGRect {
        CGRect(x: pt(7.8), y: ptH(10), width: pt(84.2), height: ptH(37.4))
    }
}

public extension Color {
    /// Bridges the framework-free `CardColor` to SwiftUI.
    init(_ cardColor: CardColor) {
        self.init(.sRGB, red: cardColor.red, green: cardColor.green, blue: cardColor.blue, opacity: 1)
    }
}

public extension CardColor {
    /// Hue 0…1, used to tint procedural backgrounds.
    var hue: Double {
        let r = red, g = green, b = blue
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        guard delta > 0.0001 else { return 0 }
        var h: Double
        if maxC == r { h = (g - b) / delta }
        else if maxC == g { h = 2 + (b - r) / delta }
        else { h = 4 + (r - g) / delta }
        h /= 6
        if h < 0 { h += 1 }
        return h
    }

    /// A readable foreground for text drawn over this colour.
    var contrastingText: CardColor { luminance > 0.6 ? .ink : .paper }
}

public extension Card {
    /// Accent colour used by the template (explicit, else derived from the content).
    var resolvedAccent: CardColor {
        if let accent { return accent }
        switch content {
        case .creature(let creature): return creature.element.color
        case .artist: return .vermilion
        case .painting: return .cobalt
        case .celestial(let object): return object.kind.color
        }
    }
}
