import CardCore
import CardPack
import CardUI
import SwiftUI

/// Pack-opening demo: a carousel of sealed packs, tap the centred one to open
/// it, swipe through the cards, come back for another.
struct BoosterDemoView: View {
    private enum Stage: Equatable {
        case choosing
        case opening(BoosterPack)
    }

    @State private var stage: Stage = .choosing
    @State private var designIndex = 0
    @State private var seed: UInt64 = 1
    @State private var opened: [Card] = []

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
            ZStack {
                switch stage {
                case .choosing:
                    chooser
                        .transition(.opacity)
                case .opening(let pack):
                    PackOpeningView(pack: pack, design: design) { cards in
                        opened.append(contentsOf: cards)
                    }
                    .id(pack.id)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: stage)
            .toolbar {
                if case .opening = stage {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            stage = .choosing
                        } label: {
                            Label("Packs", systemImage: "chevron.left")
                        }
                    }
                }
            }
            .navigationTitle("Booster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    /// Carousel on a background that takes the colours of the centred pack,
    /// top and bottom bands included.
    private var chooser: some View {
        ZStack {
            VStack(spacing: 0) {
                Color(design.topColor).opacity(0.55)
                    .frame(height: 140)
                Color(white: 0.06)
                Color(design.bottomColor).opacity(0.7)
                    .frame(height: 140)
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: designIndex)

            VStack(spacing: 12) {
                Text(design.title.uppercased())
                    .font(.system(.title, design: .rounded).weight(.black))
                    .foregroundStyle(.white)
                Text("\(design.cardCount) cards · tap the pack to open it")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                PackCarouselView(designs: Self.designs, selection: $designIndex) { index in
                    designIndex = index
                    stage = .opening(newPack())
                }
                if !opened.isEmpty {
                    Text("\(opened.count) cards collected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
    }

    private func newPack() -> BoosterPack {
        seed &+= 1
        var rng = SeededRandomNumberGenerator(seed: seed)
        return BoosterGenerator.standard.makePack(named: design.title, from: SampleLibrary.boosterPool, using: &rng)
    }
}
