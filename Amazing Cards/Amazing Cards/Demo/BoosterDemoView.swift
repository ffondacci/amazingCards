import CardCore
import CardPack
import CardUI
import SwiftUI

/// Pack-opening demo: pick a wrapper design, open packs, repeat.
struct BoosterDemoView: View {
    @State private var designIndex = 0
    @State private var seed: UInt64 = 1
    @State private var pack: BoosterPack = Self.makePack(seed: 1, design: Self.designs[0])
    @State private var opened: [Card] = []

    static let designs: [PackDesign] = [
        PackDesign(
            title: "Van Gogh",
            subtitle: "Masterpieces",
            cover: .asset("starry_night"),
            baseColors: [CardColor(hex: 0x1B2A6B), CardColor(hex: 0x0D1230)],
            foilHue: 0.6,
            emblemSymbol: "paintpalette.fill",
            bandColor: .gold
        ),
        PackDesign(
            title: "Deep Sky",
            subtitle: "Observatory",
            cover: .asset("pillars_of_creation"),
            baseColors: [CardColor(hex: 0x2A0845), CardColor(hex: 0x05020F)],
            foilHue: 0.8,
            emblemSymbol: "moon.stars.fill",
            bandColor: .nebula
        ),
        PackDesign(
            title: "Amazing",
            subtitle: "Series 1",
            cover: .asset("saturn"),
            baseColors: [CardColor(hex: 0xB3121F), CardColor(hex: 0x4A0810)],
            foilHue: 0.02,
            emblemSymbol: "sparkles",
            bandColor: .ink
        ),
    ]

    var body: some View {
        NavigationStack {
            PackOpeningView(pack: pack, design: Self.designs[designIndex]) { cards in
                opened.append(contentsOf: cards)
            }
            .id(pack.id)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Design", selection: $designIndex) {
                        ForEach(Array(Self.designs.enumerated()), id: \.offset) { index, design in
                            Text(design.title).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPack()
                    } label: {
                        Label("New pack", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("Booster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: designIndex) { _, _ in newPack() }
            .safeAreaInset(edge: .bottom) {
                if !opened.isEmpty {
                    Text("\(opened.count) cards collected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 4)
                }
            }
        }
    }

    private func newPack() {
        seed &+= 1
        pack = Self.makePack(seed: seed, design: Self.designs[designIndex])
    }

    private static func makePack(seed: UInt64, design: PackDesign) -> BoosterPack {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return BoosterGenerator.standard.makePack(named: design.title, from: SampleLibrary.boosterPool, using: &rng)
    }
}
