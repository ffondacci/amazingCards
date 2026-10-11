import CardCore
import SwiftUI

/// What every layer view needs to draw itself inside the window.
struct ParallaxLayerContext {
    var window: CGSize
    var em: CGFloat
    /// Position (0…1) and strength of the light sliding across pictures.
    var sheenX: CGFloat
    var sheenAlpha: CGFloat
    var time: TimeInterval
    var reduceMotion: Bool
}

/// One layer, drawn in a window-sized frame.
struct ParallaxLayerContent: View {
    let layer: ParallaxLayer
    let context: ParallaxLayerContext

    var body: some View {
        switch layer.content {
        case .image(let image): ParallaxImageView(layer: layer, image: image, context: context)
        case .glow(let glow): ParallaxGlowView(glow: glow, size: context.window)
        case .word(let word): ParallaxWordView(layer: layer, word: word, context: context)
        case .title(let title): ParallaxTitleView(layer: layer, title: title, context: context)
        case .box(let box): ParallaxBoxView(layer: layer, box: box, context: context)
        case .specs(let specs): ParallaxSpecsView(layer: layer, specs: specs, context: context)
        }
    }
}

// MARK: - Picture

/// The picture of an image layer, cut out on black when asked.
private struct ParallaxPicture: View {
    let image: ParallaxImage

    var body: some View {
        ArtworkView(image.artwork, contentMode: image.covers ? .fill : .fit)
            .mask {
                if image.keyedOnBlack {
                    ArtworkView(image.artwork, contentMode: image.covers ? .fill : .fit)
                        .luminanceToAlpha()
                } else {
                    Rectangle()
                }
            }
    }
}

/// The light that slides across a picture as the card tilts.
private struct ParallaxSheen<Mask: View>: View {
    let color: CardColor
    let context: ParallaxLayerContext
    let width: CGFloat
    @ViewBuilder let mask: Mask

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.38),
                .init(color: Color(color).opacity(0.5), location: 0.47),
                .init(color: Color(color).opacity(0.2), location: 0.52),
                .init(color: .clear, location: 0.62),
            ],
            startPoint: UnitPoint(x: 0, y: 0.32), endPoint: UnitPoint(x: 1, y: 0.68)
        )
        .frame(width: width * 3)
        .offset(x: width * 1.5 - 2 * width * context.sheenX - width / 2)
        .mask { mask }
        .blendMode(.screen)
        .opacity(context.sheenAlpha)
        .allowsHitTesting(false)
    }
}

struct ParallaxImageView: View {
    let layer: ParallaxLayer
    let image: ParallaxImage
    let context: ParallaxLayerContext

    var body: some View {
        if image.covers {
            ZStack {
                ParallaxPicture(image: image)
                    .frame(width: context.window.width, height: context.window.height)
                    .clipped()
                if image.sheen {
                    ParallaxSheen(color: image.sheenColor, context: context, width: context.window.width) { Rectangle() }
                        .frame(width: context.window.width, height: context.window.height)
                        .clipped()
                }
            }
        } else {
            let width = CGFloat(layer.width) * context.window.width
            let height = width / CGFloat(max(image.aspect, 0.05))
            let breath = image.breathes && !context.reduceMotion ? (1 - cos(context.time * 2 * .pi / 4.2)) / 2 : 0
            let pulse = 0.78 + 0.22 * (1 - cos(context.time * 2 * .pi / 6)) / 2
            ZStack {
                if image.glow {
                    let halo = width * CGFloat(image.glowSize)
                    EllipticalGradient(
                        stops: [
                            .init(color: Color(image.glowColor).opacity(0.62), location: 0),
                            .init(color: Color(image.glowColor).opacity(0.3), location: 0.4),
                            .init(color: Color(image.glowColor).opacity(0.1), location: 0.66),
                            .init(color: .clear, location: 0.86),
                        ]
                    )
                    .frame(width: halo, height: halo)
                    .opacity(context.reduceMotion ? 0.9 : pulse)
                }
                if image.shadow {
                    EllipticalGradient(colors: [Color(image.shadowColor).opacity(0.8), .clear])
                        .frame(width: width * 0.88, height: height * 0.12)
                        .blur(radius: 0.25 * context.em)
                        .offset(y: height / 2 + height * 0.03 - height * 0.06)
                }
                if image.reflects {
                    ParallaxPicture(image: image)
                        .frame(width: width, height: height)
                        .scaleEffect(y: -1)
                        .mask {
                            LinearGradient(stops: [.init(color: .black.opacity(0.95), location: 0), .init(color: .clear, location: 0.32)], startPoint: .top, endPoint: .bottom)
                        }
                        .opacity(0.28)
                        .offset(y: height)
                }
                ZStack {
                    ParallaxPicture(image: image)
                        .frame(width: width, height: height)
                        .shadow(color: image.glow ? Color(image.glowColor).opacity(0.6) : .clear, radius: image.glow ? 0.9 * context.em : 0)
                    if image.sheen {
                        ParallaxSheen(color: image.sheenColor, context: context, width: width) {
                            ParallaxPicture(image: image).frame(width: width, height: height)
                        }
                        .frame(width: width, height: height)
                    }
                }
                .scaleEffect(x: 1 + 0.008 * breath, y: 1 + 0.02 * breath, anchor: .bottom)
            }
            .frame(width: width, height: height)
            .position(x: CGFloat(layer.x) * context.window.width, y: CGFloat(layer.y) * context.window.height)
        }
    }
}

// MARK: - Glow backdrop

struct ParallaxGlowView: View {
    let glow: ParallaxGlow
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        ZStack {
            // Tone: a wide dark field with a light pool near the top.
            EllipticalGradient(
                stops: [
                    .init(color: Color(glow.middle), location: 0),
                    .init(color: Color(glow.middle.mixed(with: glow.edge, 0.45)), location: 0.48),
                    .init(color: Color(glow.edge), location: 0.8),
                    .init(color: Color(glow.edge.mixed(with: .black, 0.55)), location: 1),
                ]
            )
            .frame(width: w * 2.4, height: h * 1.8)
            .position(x: w * 0.5, y: h * 0.35)
            EllipticalGradient(
                stops: [
                    .init(color: Color(glow.light).opacity(0.95), location: 0),
                    .init(color: Color(glow.light.mixed(with: glow.middle, 0.4)).opacity(0.55), location: 0.45),
                    .init(color: .clear, location: 0.75),
                ]
            )
            .frame(width: w * 1.4, height: h * 0.9)
            .position(x: w * 0.5, y: h * 0.3)
            if glow.rays {
                AngularGradient(stops: Self.rayStops(Color(glow.raysColor).opacity(0.2)), center: UnitPoint(x: 0.5, y: 0.02))
                    .frame(width: w, height: h)
                    .mask {
                        EllipticalGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.75)])
                            .frame(width: w * 1.2, height: h * 1.2)
                            .position(x: w * 0.5, y: h * 0.1)
                    }
                    .opacity(0.55)
                    .blendMode(.screen)
            }
            if glow.rings {
                Circle().stroke(Color(glow.ringColor).opacity(0.26), lineWidth: 1)
                    .frame(width: w * 1.18, height: w * 1.18)
                    .position(x: w * 0.5, y: h * 0.35)
                Circle().stroke(Color(glow.ringColor).opacity(0.12), lineWidth: 1)
                    .frame(width: w * 0.84, height: w * 0.84)
                    .position(x: w * 0.5, y: h * 0.35)
                ForEach([28.0, -28.0], id: \.self) { angle in
                    LinearGradient(colors: [.clear, Color(glow.ringColor).opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(width: 1, height: h * 1.4)
                        .rotationEffect(.degrees(angle))
                        .position(x: w * 0.5, y: h * 0.35)
                }
            }
            if glow.floor {
                LinearGradient(
                    stops: [
                        .init(color: Color(glow.floorColor).opacity(0), location: 0),
                        .init(color: Color(glow.floorColor).opacity(0.72), location: 0.22),
                        .init(color: Color(glow.floorColor).opacity(0.96), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: w * 1.2, height: h * 0.42)
                .position(x: w * 0.5, y: h * 0.79)
                LinearGradient(colors: [.clear, Color(glow.lineColor).opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: w, height: 1)
                    .position(x: w * 0.5, y: h * 0.625)
                EllipticalGradient(colors: [Color(glow.spotColor).opacity(0.55), .clear])
                    .frame(width: w * 0.84, height: h * 0.16)
                    .position(x: w * 0.5, y: h * 0.64)
                    .blendMode(.screen)
            }
        }
        .frame(width: w, height: h)
        .clipped()
    }

    /// Thin bright wedges every 7°, like the stylesheet's repeating conic gradient.
    private static func rayStops(_ color: Color) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        var angle = 0.0
        while angle < 360 {
            let a = angle / 360, b = (angle + 2.2) / 360
            stops.append(.init(color: color, location: a))
            stops.append(.init(color: color, location: min(1, b)))
            stops.append(.init(color: .clear, location: min(1, b + 0.0001)))
            stops.append(.init(color: .clear, location: min(1, (angle + 7) / 360)))
            angle += 7
        }
        return stops
    }
}

// MARK: - Word, title, box, specs

struct ParallaxWordView: View {
    let layer: ParallaxLayer
    let word: ParallaxWord
    let context: ParallaxLayerContext

    var body: some View {
        let width = CGFloat(layer.width) * context.window.width
        let text = Text(word.text)
            .font(.system(size: 400, weight: .black))
            .fontWidth(.compressed)
            .lineLimit(1)
            .minimumScaleFactor(0.01)
        ZStack {
            ForEach([CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: -1), CGPoint(x: 0, y: 1)], id: \.x) { d in
                text.foregroundStyle(Color(word.stroke).opacity(0.16)).offset(x: d.x, y: d.y)
            }
            text.foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color(word.top).opacity(0.92), location: 0),
                        .init(color: Color(word.bottom).opacity(0.75), location: 0.55),
                        .init(color: Color(word.bottom).opacity(0), location: 0.92),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        .frame(width: width)
        .scaleEffect(y: CGFloat(word.stretch))
        .position(x: CGFloat(layer.x) * context.window.width, y: CGFloat(layer.y) * context.window.height)
    }
}

/// Shield badge of a title layer.
struct ParallaxBadge: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 40, h = rect.height / 48
        var p = Path()
        p.move(to: CGPoint(x: 20 * w, y: 2.5 * h))
        p.addLine(to: CGPoint(x: 37 * w, y: 8.5 * h))
        p.addLine(to: CGPoint(x: 37 * w, y: 24 * h))
        p.addCurve(to: CGPoint(x: 20 * w, y: 45.5 * h), control1: CGPoint(x: 37 * w, y: 34.6 * h), control2: CGPoint(x: 29.6 * w, y: 42.6 * h))
        p.addCurve(to: CGPoint(x: 3 * w, y: 24 * h), control1: CGPoint(x: 10.4 * w, y: 42.6 * h), control2: CGPoint(x: 3 * w, y: 34.6 * h))
        p.addLine(to: CGPoint(x: 3 * w, y: 8.5 * h))
        p.closeSubpath()
        return p
    }
}

struct ParallaxTitleView: View {
    let layer: ParallaxLayer
    let title: ParallaxTitle
    let context: ParallaxLayerContext

    var body: some View {
        let em = CGFloat(layer.width) * context.em
        VStack(spacing: 0) {
            if title.badge {
                ZStack {
                    ParallaxBadge().stroke(Color(title.badgeColor), lineWidth: em * 0.08)
                    ParallaxBadge().stroke(Color(title.badgeColor).opacity(0.6), lineWidth: em * 0.035).padding(em * 0.22)
                    Path { p in
                        p.move(to: CGPoint(x: em * 0.63, y: em * 0.95))
                        p.addLine(to: CGPoint(x: em * 1.1, y: em * 1.68))
                        p.addLine(to: CGPoint(x: em * 1.57, y: em * 0.95))
                    }
                    .stroke(Color(title.badgeColor), style: StrokeStyle(lineWidth: em * 0.14, lineCap: .round, lineJoin: .round))
                    Capsule().fill(Color(title.badgeColor)).frame(width: em * 0.66, height: em * 0.08).offset(y: -em * 0.6)
                }
                .frame(width: em * 2.2, height: em * 2.6)
                .shadow(color: Color(title.glowColor).opacity(0.6), radius: em * 0.5)
            }
            Text(title.brand)
                .font(.system(size: em * 0.74, weight: .semibold))
                .tracking(em * 0.75)
                .foregroundStyle(Color(title.brandColor))
                .padding(.top, em * 0.55)
                .padding(.leading, em * 0.75)
            Text(title.model)
                .font(.system(size: em * 1.75, weight: .heavy, design: .rounded).italic())
                .tracking(em * 0.14)
                .foregroundStyle(Color(title.modelColor))
                .shadow(color: Color(title.glowColor).opacity(0.55), radius: em * 0.6)
                .padding(.top, em * 0.18)
                .padding(.leading, em * 0.14)
        }
        .lineLimit(1)
        .fixedSize()
        .position(x: CGFloat(layer.x) * context.window.width, y: CGFloat(layer.y) * context.window.height)
    }
}

struct ParallaxBoxView: View {
    let layer: ParallaxLayer
    let box: ParallaxBox
    let context: ParallaxLayerContext

    var body: some View {
        let em = context.em
        VStack(spacing: em * 0.5) {
            Text(box.heading)
                .font(.system(size: em * 1.02, weight: .heavy, design: .rounded).italic())
                .tracking(em * 0.14)
                .foregroundStyle(Color(box.headingColor))
            Text(box.body.uppercased())
                .font(.system(size: em * 0.56, weight: .medium))
                .tracking(em * 0.12)
                .lineSpacing(em * 0.56 * 0.7)
                .foregroundStyle(Color(box.textColor).opacity(0.8))
        }
        .multilineTextAlignment(.center)
        .padding(.top, em * 0.75)
        .padding(.horizontal, em * 1.1)
        .padding(.bottom, em * 0.8)
        .frame(width: CGFloat(layer.width) * context.window.width)
        .background(LinearGradient(colors: [Color(box.fillColor).opacity(0.55), Color(box.fillColor).opacity(0.35)], startPoint: .top, endPoint: .bottom))
        .overlay(Rectangle().stroke(Color(box.borderColor).opacity(0.5), lineWidth: 1))
        .position(x: CGFloat(layer.x) * context.window.width, y: CGFloat(layer.y) * context.window.height)
    }
}

struct ParallaxSpecsView: View {
    let layer: ParallaxLayer
    let specs: ParallaxSpecs
    let context: ParallaxLayerContext

    var body: some View {
        let em = context.em
        HStack(spacing: 0) {
            ForEach(Array(specs.items.prefix(4).enumerated()), id: \.offset) { index, spec in
                HStack(spacing: em * 0.45) {
                    if !spec.symbol.isEmpty {
                        Image(systemName: spec.symbol)
                            .font(.system(size: em * 1.3, weight: .regular))
                            .foregroundStyle(Color(specs.iconColor))
                            .frame(width: em * 1.6, height: em * 1.6)
                    }
                    VStack(alignment: .leading, spacing: em * 0.35) {
                        HStack(alignment: .firstTextBaseline, spacing: em * 0.18) {
                            Text(spec.value).font(.system(size: em * 1.05, weight: .bold))
                            Text(spec.unit).font(.system(size: em * 0.61, weight: .semibold)).opacity(0.85)
                        }
                        Text(spec.label.uppercased())
                            .font(.system(size: em * 0.48, weight: .medium))
                            .tracking(em * 0.07)
                            .opacity(0.62)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    if index > 0 {
                        Rectangle().fill(Color(specs.lineColor).opacity(0.3)).frame(width: 1).padding(.vertical, em * 0.4)
                    }
                }
            }
        }
        .foregroundStyle(Color(specs.textColor))
        .frame(width: CGFloat(layer.width) * context.window.width)
        .position(x: CGFloat(layer.x) * context.window.width, y: CGFloat(layer.y) * context.window.height)
    }
}
