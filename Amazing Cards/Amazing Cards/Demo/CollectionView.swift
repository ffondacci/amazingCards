import CardCore
import CardFX
import CardUI
import SwiftUI

/// Adaptive grid of every sample card. Tap a card for the interactive view.
struct CollectionView: View {
    @Binding var theme: CardTheme
    @State private var selected: Card?
    @State private var selectedParallax: ParallaxDesign?
    @State private var showsFinish = true

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 16)], spacing: 16) {
                    ForEach(SampleLibrary.all) { card in
                        Button {
                            selected = card
                        } label: {
                            VStack(spacing: 8) {
                                CardView(card: card, showsFinish: showsFinish)
                                    .cardMotionIdle(animates: false)
                                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                                HStack(spacing: 4) {
                                    RaritySymbol(card.rarity, size: 10)
                                    Text(card.finish.displayName)
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(card.title)
                    }
                }
                .padding()

                // Layered cards: tilt them and the layers slide apart.
                Text("Parallax")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 16)], spacing: 16) {
                    ForEach(SampleLibrary.parallaxDesigns) { design in
                        Button {
                            selectedParallax = design
                        } label: {
                            VStack(spacing: 8) {
                                ParallaxCardView(design: design, size: 1.35)
                                    .aspectRatio(ParallaxDesign.aspectRatio, contentMode: .fit)
                                    .allowsHitTesting(false)
                                Text(design.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(design.name)
                    }
                }
                .padding()
            }
            .background(Color(white: 0.06))
            .navigationTitle("Collection")
            .navigationDestination(item: $selected) { card in
                CardDetailView(card: card)
            }
            .navigationDestination(item: $selectedParallax) { design in
                ParallaxDetailView(design: design)
            }
            .onAppear {
                // `-parallax saturn` opens a parallax card straight away, `-card creature-vincent` a card (screenshots, QA).
                if let wanted = UserDefaults.standard.string(forKey: "parallax"),
                   let design = SampleLibrary.parallaxDesigns.first(where: { $0.id.contains(wanted) }) {
                    selectedParallax = design
                }
                if let wanted = UserDefaults.standard.string(forKey: "card"),
                   let card = SampleLibrary.all.first(where: { $0.id.rawValue == wanted }) {
                    selected = card
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Theme", selection: $theme) {
                            ForEach(CardTheme.presets, id: \.self) { preset in
                                Text(preset.name).tag(preset)
                            }
                        }
                        Toggle("Foil in grid", isOn: $showsFinish)
                    } label: {
                        Label("Theme", systemImage: "paintbrush")
                    }
                }
            }
        }
    }
}

/// Full-size interactive card with finish picker, flip and gyroscope toggle.
struct CardDetailView: View {
    let card: Card
    @State private var finish: CardFinish
    @State private var isFaceUp = true
    @State private var usesGyro = true

    init(card: Card) {
        self.card = card
        self._finish = State(initialValue: card.finish)
    }

    private var current: Card { card.with(finish: finish) }

    var body: some View {
        VStack(spacing: 20) {
            CardMotionStage(
                usesDeviceMotion: usesGyro,
                animates: FinishRecipe.recipe(for: finish, template: card.template).isTimeDriven
            ) {
                FlippableCardView(card: current, isFaceUp: $isFaceUp, flipsOnTap: false)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 28)
            .frame(maxHeight: .infinity)

            VStack(spacing: 12) {
                Picker("Finish", selection: $finish) {
                    ForEach(CardFinish.allCases, id: \.self) { finish in
                        Text(finish.displayName).tag(finish)
                    }
                }
                .pickerStyle(.menu)
                HStack(spacing: 16) {
                    Button {
                        withAnimation(.cardFlip) { isFaceUp.toggle() }
                    } label: {
                        Label("Flip", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    }
                    .buttonStyle(.bordered)
                    Toggle("Gyroscope", isOn: $usesGyro)
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                }
                Text("Drag on the card to tilt it. \(card.template.displayName) · \(card.rarity.displayName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)
        }
        .padding(.top, 8)
        .background(Color(white: 0.06).ignoresSafeArea())
        .navigationTitle(card.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// A parallax card full size, with its three views and a flip.
struct ParallaxDetailView: View {
    let design: ParallaxDesign
    @State private var mode: ParallaxMode = .card
    @State private var flips = 0
    @State private var deviceMotion = DeviceMotionSource()

    var body: some View {
        VStack(spacing: 16) {
            ParallaxCardView(design: design, mode: mode, flips: flips)
                .cardMotion(tilt: deviceMotion.tilt, animates: false)
                .onAppear { deviceMotion.start() }
                .onDisappear { deviceMotion.stop() }
            Picker("View", selection: $mode) {
                Text("Card").tag(ParallaxMode.card)
                Text("Layers in 3D").tag(ParallaxMode.stack)
                Text("Side by side").tag(ParallaxMode.spread)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            Button("Flip") { flips += 1 }
                .buttonStyle(.bordered)
                .disabled(mode != .card)
            Text("\(design.layers.count) layers · drag it, tap twice to flip")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.03, green: 0.024, blue: 0.1))
        .navigationTitle(design.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
