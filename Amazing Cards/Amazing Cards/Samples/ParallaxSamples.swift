import CardCore

/// Two parallax cards built from the sample pictures: a planet poster and
/// a neon window with Vincent in a starry night.
extension SampleLibrary {
    static let parallaxDesigns: [ParallaxDesign] = [saturnPoster, vincentWindow]

    static let saturnPoster = ParallaxDesign(
        id: "parallax-saturn-poster",
        name: "Saturn poster",
        style: .rim,
        layers: [
            ParallaxLayer(id: "backdrop", name: "Backdrop", depth: 5.5, content: .glow(ParallaxGlow(
                light: CardColor(hex: 0xFFB347), middle: CardColor(hex: 0x8A4A0C), edge: CardColor(hex: 0x2A1606),
                raysColor: CardColor(hex: 0xFFD08A), ringColor: CardColor(hex: 0xFFC58A),
                floorColor: CardColor(hex: 0x0E0803), lineColor: CardColor(hex: 0xFFC58A), spotColor: CardColor(hex: 0xFF9A3D)
            ))),
            ParallaxLayer(id: "word", name: "Big word", depth: 2.4, y: 0.31, width: 0.86, content: .word(ParallaxWord(
                text: "SATURN", top: CardColor(hex: 0x6B3A0F), bottom: CardColor(hex: 0x4A2608), stroke: CardColor(hex: 0xFFB870), stretch: 1.55
            ))),
            ParallaxLayer(id: "planet", name: "Planet", depth: -5.6, y: 0.479, width: 1.08, pops: true, content: .image(ParallaxImage(
                artwork: .asset("saturn"), aspect: 1280.0 / 620.0, keyedOnBlack: true, shadow: true, reflects: true, sheen: true
            ))),
            ParallaxLayer(id: "title", name: "Title", depth: -2.8, y: 0.092, pops: true, content: .title(ParallaxTitle(
                brand: "CELESTIAL", model: "SATURN", brandColor: CardColor(hex: 0xF9F0E0), modelColor: .white,
                glowColor: CardColor(hex: 0xFFB347), badgeColor: CardColor(hex: 0xFFE0B2)
            ))),
            ParallaxLayer(id: "copy", name: "Text box", depth: -2.2, y: 0.82, width: 0.72, pops: true, content: .box(ParallaxBox(
                heading: "SATURN · PLANET VI",
                body: "The ringed giant seen at equinox by Cassini, rings edge-on to the Sun and casting a thin shadow.",
                headingColor: CardColor(hex: 0xFFB347), textColor: CardColor(hex: 0xF3E6D6),
                borderColor: CardColor(hex: 0xFF9A3D), fillColor: CardColor(hex: 0x1E1208)
            ))),
            ParallaxLayer(id: "specs", name: "Specs", depth: -3.2, y: 0.926, width: 0.94, pops: true, content: .specs(ParallaxSpecs(
                items: [
                    .init(value: "1.4", unit: "bn km", label: "Distance", symbol: "arrow.left.and.right"),
                    .init(value: "0.5", unit: "mag", label: "Magnitude", symbol: "sparkles"),
                    .init(value: "18", unit: "″", label: "Size", symbol: "ruler"),
                    .init(value: "10.7", unit: "h", label: "Day", symbol: "clock"),
                ],
                textColor: .white, iconColor: .white, lineColor: CardColor(hex: 0xFFD6A8)
            ))),
        ],
        frame: ParallaxFrame(
            edge1: CardColor(hex: 0xE8B923), edge2: CardColor(hex: 0x3A2A10), edge3: CardColor(hex: 0xFFD27A), glow: 0,
            plate: CardColor(hex: 0x140F08), line: CardColor(hex: 0xFFC66B), shade: .black, cornerRadius: 1.6 / 40
        ),
        back: ParallaxBack(
            title: "SATURN", subtitle: "Collector edition · 008 / 010", pictureLayer: "planet",
            background: CardColor(hex: 0xB65A12), edge: CardColor(hex: 0x0B0604), accent: CardColor(hex: 0xFFB347),
            titleColor: .white, subtitleColor: CardColor(hex: 0xF9EBE7)
        )
    )

    static let vincentWindow = ParallaxDesign(
        id: "parallax-vincent-window",
        name: "Vincent's night",
        style: .neon,
        layers: [
            ParallaxLayer(id: "sky", name: "Sky", depth: 8.5, content: .image(ParallaxImage(artwork: .asset("starry_night"), covers: true))),
            ParallaxLayer(id: "moon", name: "Planet", depth: 11, x: 0.74, y: 0.22, width: 0.36, content: .image(ParallaxImage(
                artwork: .asset("saturn"), aspect: 1280.0 / 620.0, keyedOnBlack: true, glow: true, glowColor: CardColor(hex: 0xC8AAFF), glowSize: 2
            ))),
            ParallaxLayer(id: "word", name: "Big word", depth: 3.4, y: 0.42, width: 0.9, content: .word(ParallaxWord(
                text: "VINCENT", top: CardColor(hex: 0x6E4FD0), bottom: CardColor(hex: 0x2B1A6B), stroke: CardColor(hex: 0xCDAAFF), stretch: 1.3
            ))),
            ParallaxLayer(id: "hero", name: "Vincent", depth: 0.9, y: 0.6, width: 0.66, content: .image(ParallaxImage(
                artwork: .asset("vangogh_sticker"), aspect: 1024.0 / 990.0, glow: true, glowColor: CardColor(hex: 0xAA5AFF), glowSize: 0.6,
                sheen: true, sheenColor: CardColor(hex: 0xFFEBFF), breathes: true
            ))),
        ],
        frame: ParallaxFrame(
            edge1: CardColor(hex: 0xFF3FD8), edge2: CardColor(hex: 0x9B5CFF), edge3: CardColor(hex: 0x3D7BFF), glow: 1,
            plate: CardColor(hex: 0x0B0820), line: CardColor(hex: 0xCDAAFF), shade: CardColor(hex: 0x08041E), cornerRadius: 1.9 / 40,
            specks: ParallaxSpecks(kind: .stardust)
        ),
        back: ParallaxBack(
            title: "VINCENT", subtitle: "Post-impressionist · No. 001", pictureLayer: "hero",
            background: CardColor(hex: 0x2A1660), edge: CardColor(hex: 0x06041A), accent: CardColor(hex: 0xBE78FF),
            titleColor: CardColor(hex: 0xD9B8FF), subtitleColor: CardColor(hex: 0xDCC8FF)
        )
    )
}
