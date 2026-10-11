import CardCore
import CardUI
import SwiftUI
import UIKit

/// The app's own artworks: a SwiftUI aurora and a comet drawn with UIKit,
/// both reachable from any card, pack or parallax layer through
/// `CardArtwork.custom("…")`.
enum CustomArtworks {
    static let aurora = "aurora"
    static let comet = "uikit-comet"

    /// Hooked on the root view; the stage's print renderer gets it from there.
    static let provider = ArtworkProvider { key in
        switch key {
        case aurora: AnyView(AuroraView())
        case comet: AnyView(Image(uiImage: CometRenderer.image(size: CGSize(width: 640, height: 900))).resizable().aspectRatio(contentMode: .fill))
        default: nil
        }
    }
}

/// Northern lights over a dark sea, drawn in SwiftUI: a night gradient,
/// three curtains of light and a sprinkle of stars. Fills whatever frame
/// it is given.
struct AuroraView: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.1), Color(red: 0.0, green: 0.07, blue: 0.14), Color(red: 0.0, green: 0.02, blue: 0.05)], startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    // Stars.
                    var seed: UInt32 = 7
                    func next() -> CGFloat { seed = seed &* 1664525 &+ 1013904223; return CGFloat(seed >> 8) / CGFloat(1 << 24) }
                    for _ in 0..<140 {
                        let x = next() * size.width, y = next() * size.height * 0.7, r = 0.4 + next() * 1.4
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.35 + Double(next()) * 0.6)))
                    }
                    // Curtains: tall wavy bands, bright at the bottom edge.
                    for (index, tint) in [Color(red: 0.2, green: 1, blue: 0.6), Color(red: 0.35, green: 0.8, blue: 1), Color(red: 0.8, green: 0.4, blue: 1)].enumerated() {
                        var path = Path()
                        let base = size.height * (0.42 + CGFloat(index) * 0.08)
                        path.move(to: CGPoint(x: -size.width * 0.1, y: base))
                        var x: CGFloat = -size.width * 0.1
                        while x <= size.width * 1.1 {
                            let wave = sin(x / size.width * .pi * (2.2 + CGFloat(index) * 0.7) + CGFloat(index)) * size.height * 0.05
                            path.addLine(to: CGPoint(x: x, y: base + wave))
                            x += size.width * 0.02
                        }
                        path.addLine(to: CGPoint(x: size.width * 1.1, y: -size.height * 0.1))
                        path.addLine(to: CGPoint(x: -size.width * 0.1, y: -size.height * 0.1))
                        path.closeSubpath()
                        context.fill(path, with: .linearGradient(
                            Gradient(stops: [.init(color: tint.opacity(0), location: 0), .init(color: tint.opacity(0.18), location: 0.55), .init(color: tint.opacity(0.75), location: 1)]),
                            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: base)
                        ))
                    }
                    // The sea: a dark band with the lights mirrored faintly.
                    let sea = CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.28)
                    context.fill(Path(sea), with: .linearGradient(
                        Gradient(colors: [Color(red: 0.05, green: 0.25, blue: 0.3).opacity(0.8), Color(red: 0, green: 0.02, blue: 0.05)]),
                        startPoint: CGPoint(x: 0, y: sea.minY), endPoint: CGPoint(x: 0, y: sea.maxY)
                    ))
                }
                Text("AURORA")
                    .font(.system(size: w * 0.11, weight: .black, design: .rounded))
                    .tracking(w * 0.02)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: Color(red: 0.2, green: 1, blue: 0.6).opacity(0.8), radius: w * 0.03)
                    .position(x: w / 2, y: h * 0.86)
            }
        }
    }
}

/// A comet drawn with UIKit (layers and Core Graphics) and rendered into
/// an image, the way a UIKit screen hands its drawing to the cards.
enum CometRenderer {
    @MainActor
    static func image(size: CGSize) -> UIImage {
        let view = UIView(frame: CGRect(origin: .zero, size: size))
        let sky = CAGradientLayer()
        sky.frame = view.bounds
        sky.colors = [UIColor(red: 0.04, green: 0.0, blue: 0.1, alpha: 1).cgColor, UIColor(red: 0.12, green: 0.02, blue: 0.2, alpha: 1).cgColor, UIColor.black.cgColor]
        view.layer.addSublayer(sky)
        let tail = CAGradientLayer()
        tail.frame = view.bounds
        tail.type = .radial
        tail.startPoint = CGPoint(x: 0.62, y: 0.4)
        tail.endPoint = CGPoint(x: 0.0, y: 1.0)
        tail.colors = [UIColor(red: 0.6, green: 0.9, blue: 1, alpha: 0.9).cgColor, UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 0.25).cgColor, UIColor.clear.cgColor]
        tail.transform = CATransform3DMakeRotation(0.35, 0, 0, 1)
        view.layer.addSublayer(tail)
        let head = CAShapeLayer()
        let r = size.width * 0.07
        head.path = UIBezierPath(ovalIn: CGRect(x: size.width * 0.62 - r, y: size.height * 0.4 - r, width: 2 * r, height: 2 * r)).cgPath
        head.fillColor = UIColor.white.cgColor
        head.shadowColor = UIColor(red: 0.7, green: 0.9, blue: 1, alpha: 1).cgColor
        head.shadowOpacity = 1
        head.shadowRadius = r
        head.shadowOffset = .zero
        view.layer.addSublayer(head)
        let label = UILabel(frame: CGRect(x: 0, y: size.height * 0.8, width: size.width, height: size.height * 0.12))
        label.text = "UIKIT"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: size.width * 0.1, weight: .black)
        label.textColor = UIColor(white: 1, alpha: 0.85)
        view.addSubview(label)
        return UIGraphicsImageRenderer(size: size).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }
}
