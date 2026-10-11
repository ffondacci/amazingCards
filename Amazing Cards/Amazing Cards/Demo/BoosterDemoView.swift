import CardCore
import CardPack
import CardStage
import CardUI
import ImageIO
import SwiftUI

/// Pack-opening demo: the 3D studio of sealed packs; tap the front one to
/// open it, tap through the cards, come back for another.
struct BoosterDemoView: View {
    @State private var designIndex = 0
    @State private var seed: UInt64 = 1
    @State private var opened: [Card] = []
    @State private var prints = PackPrints()
    @State private var phase: StagePhase = .idle
    @Environment(\.artworkProvider) private var artworkProvider
    /// The next pack and its pictures, prepared while the carousel idles.
    @State private var nextDeal: (pack: BoosterPack, skins: [CardSkin])?
    @State private var dealt = 0
    @State private var night = false
    /// How the front pack opens; `-opening melt` picks one at launch.
    @State private var opening: OpeningStyle = UserDefaults.standard.string(forKey: "opening").flatMap(OpeningStyle.init(rawValue:)) ?? .tear
    /// `-captureAfter 8` saves the stage frame to Documents/capture.png after 8 s
    /// (validation on a device without a screenshot tool).
    private let captureAfter = UserDefaults.standard.double(forKey: "captureAfter")
    /// `-openAfter 2` opens the front pack by itself after 2 s (validation without a finger).
    private let openAfter = UserDefaults.standard.double(forKey: "openAfter")

    static let designs: [PackDesign] = [
        PackDesign(
            title: "Masterpieces",
            subtitle: "Van Gogh",
            setCode: "S1",
            cover: .asset("starry_night"),
            topColor: CardColor(hex: 0x1B2A6B),
            bottomColor: CardColor(hex: 0x0B1030),
            accent: .gold,
            foilHue: 0.6,
            emblemSymbol: "paintpalette.fill"
        ),
        PackDesign(
            title: "Deep Sky",
            subtitle: "Observatory",
            setCode: "S1",
            cover: .asset("pillars_of_creation"),
            topColor: CardColor(hex: 0x2A0845),
            bottomColor: CardColor(hex: 0x05020F),
            accent: .aurora,
            foilHue: 0.8,
            emblemSymbol: "moon.stars.fill"
        ),
        PackDesign(
            title: "Aurora",
            subtitle: "Drawn in SwiftUI",
            setCode: "S1",
            cover: .custom(CustomArtworks.aurora),
            topColor: CardColor(hex: 0x063D3A),
            bottomColor: CardColor(hex: 0x02110F),
            accent: CardColor(hex: 0x5CFFB0),
            foilHue: 0.45,
            emblemSymbol: "sparkles"
        ),
        PackDesign(
            title: "Amazing",
            subtitle: "Series 1",
            setCode: "S1",
            cover: .asset("saturn"),
            topColor: CardColor(hex: 0xB3121F),
            bottomColor: CardColor(hex: 0x3A0710),
            accent: CardColor(hex: 0xFFC53D),
            foilHue: 0.02,
            emblemSymbol: "sparkles"
        ),
    ]

    private var design: PackDesign { Self.designs[designIndex] }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PackStageView(designs: Self.designs, settings: StageSettings(lighting: night ? .night : .studio, opening: opening), selection: $designIndex, preparedCards: nextDeal?.skins ?? [], capturable: captureAfter > 0, onPhase: { phase = $0 }, onScene: scheduleCapture) { index in
                    designIndex = index
                    let deal: (pack: BoosterPack, skins: [CardSkin])
                    if let ready = nextDeal {
                        deal = ready
                    } else {
                        let pack = newPack()
                        deal = (pack, prints.cardSkins(for: pack.cards))
                    }
                    nextDeal = nil
                    dealt += 1
                    opened.append(contentsOf: deal.pack.cards)
                    return deal.skins
                }
                .task(id: dealt) {
                    // The dealt cards are rendered to pictures, outside the environment.
                    if dealt == 0 { prints.artworkProvider = artworkProvider }
                    await prints.prepareCards(SampleLibrary.boosterPool)
                    guard !Task.isCancelled, nextDeal == nil else { return }
                    let pack = newPack()
                    let skins = await prints.cardSkins(for: pack.cards)
                    if !Task.isCancelled, !skins.isEmpty { nextDeal = (pack, skins) }
                }

                if phase == .idle {
                    VStack(spacing: 6) {
                        Text(design.title.uppercased())
                            .font(.system(.title, design: .rounded).weight(.black))
                            .foregroundStyle(night ? .white : Color(white: 0.12))
                        Text("\(design.cardCount) cards · tap the pack to open it")
                            .font(.footnote)
                            .foregroundStyle(night ? .white.opacity(0.7) : Color(white: 0.35))
                        if !opened.isEmpty {
                            Text("\(opened.count) cards collected")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(night ? .white.opacity(0.7) : Color(white: 0.35))
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                // The six ways to open a pack, like the studio's pill.
                if phase == .idle {
                    OpeningPicker(selection: $opening, night: night)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: designIndex)
            .animation(.easeInOut(duration: 0.3), value: phase)
            .navigationTitle("Booster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if phase == .idle {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            night.toggle()
                        } label: {
                            Label(night ? "Studio" : "Night", systemImage: night ? "sun.max" : "moon.stars")
                        }
                    }
                }
            }
        }
    }

    private func scheduleCapture(_ scene: StageScene) {
        if openAfter > 0 {
            Task {
                try? await Task.sleep(for: .seconds(openAfter))
                scene.open(scene.frontIndex)
            }
        }
        guard captureAfter > 0 else { return }
        Task {
            try? await Task.sleep(for: .seconds(captureAfter))
            scene.captureRequest = { image in
                let url = URL.documentsDirectory.appending(path: "capture.png")
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            }
        }
    }

    private func newPack() -> BoosterPack {
        seed &+= 1
        var rng = SeededRandomNumberGenerator(seed: seed)
        return BoosterGenerator.standard.makePack(named: design.title, from: SampleLibrary.boosterPool, using: &rng)
    }
}


/// Horizontal pill of the opening styles.
private struct OpeningPicker: View {
    @Binding var selection: OpeningStyle
    var night: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(Array(OpeningStyle.allCases.enumerated()), id: \.element) { index, style in
                    let selected = style == selection
                    Button {
                        selection = style
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.semibold))
                                .opacity(0.6)
                            Text(style.rawValue.capitalized)
                                .font(.footnote.weight(.semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selected ? (night ? Color.white.opacity(0.18) : Color.white) : .clear, in: Capsule())
                        .foregroundStyle(night ? .white : (selected ? Color(white: 0.1) : Color(white: 0.35)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .scrollIndicators(.hidden)
        .background(.regularMaterial, in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: 380)
        .accessibilityLabel("Opening style")
    }
}
