import CardCore
import CardFX
import CardStage
import CardUI
import SwiftUI

/// The 3D carousel of sealed packs: every design is printed on a foil
/// pouch standing in the studio of `CardStage`. Drag a pack to turn it,
/// drag beside it to browse, tap the front one to open it.
public struct PackStageView: View {
    public var designs: [PackDesign]
    public var settings: StageSettings
    /// Index of the design facing the camera.
    @Binding public var selection: Int
    /// Called with the index of the design when the front pack is tapped:
    /// returns the cards to deal, or nil to leave the pack sealed.
    public var onOpen: (Int) -> [CardSkin]?
    /// Called whenever the stage changes phase.
    public var onPhase: ((StagePhase) -> Void)?
    /// Cards likely to be dealt next, uploaded ahead of the tap.
    public var preparedCards: [CardSkin]
    /// The scene, for hosts that want to drive it (open, exit, capture a frame).
    public var onScene: ((StageScene) -> Void)?
    /// Lets the host read frames back through `StageScene.captureRequest`.
    public var capturable: Bool

    @State private var scene: StageScene
    @State private var prints = PackPrints()
    @State private var skins: [Int: PackSkin] = [:]
    @Environment(\.cardMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.artworkProvider) private var artworkProvider

    public init(
        designs: [PackDesign],
        settings: StageSettings = .standard,
        selection: Binding<Int>,
        preparedCards: [CardSkin] = [],
        capturable: Bool = false,
        onPhase: ((StagePhase) -> Void)? = nil,
        onScene: ((StageScene) -> Void)? = nil,
        onOpen: @escaping (Int) -> [CardSkin]?
    ) {
        self.designs = designs
        self.settings = settings
        self._selection = selection
        self.preparedCards = preparedCards
        self.capturable = capturable
        self.onPhase = onPhase
        self.onScene = onScene
        self.onOpen = onOpen
        var initial = settings
        initial.packs = max(settings.packs, designs.count)
        _scene = State(initialValue: StageScene(settings: initial))
    }

    public var body: some View {
        StageView(scene: scene, skins: skins, capturable: capturable)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                if let hint = scene.hint {
                    Text(hint)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(scene.settings.lighting == .night ? .white : Color(white: 0.15))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if scene.phase != .idle {
                    Button {
                        scene.exit()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(scene.settings.lighting == .night ? .white : Color(white: 0.15))
                            .frame(width: 40, height: 40)
                            .background(.regularMaterial, in: Circle())
                    }
                    .padding(16)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: scene.hint)
            .animation(.easeOut(duration: 0.25), value: scene.phase)
            .task(id: designs) {
                prints.artworkProvider = artworkProvider
                await prints.prepare(designs)
                guard !Task.isCancelled, !designs.isEmpty else { return }
                var next: [Int: PackSkin] = [:]
                for index in 0..<scene.settings.packs {
                    next[index] = prints.skin(for: designs[index % designs.count])
                }
                skins = next
            }
            .onChange(of: motion.tilt, initial: true) { _, tilt in
                scene.setDeviceTilt(tilt)
            }
            .onChange(of: scene.frontIndex, initial: true) { _, front in
                guard !designs.isEmpty else { return }
                selection = front % designs.count
            }
            .onChange(of: preparedCards.map(\.id), initial: true) { _, _ in
                scene.preparedCards = preparedCards
            }
            .onChange(of: settings, initial: true) { _, settings in
                var applied = settings
                applied.packs = max(settings.packs, designs.count)
                applied.floats = settings.floats && !reduceMotion
                scene.settings = applied
            }
            .onAppear {
                scene.onOpen = { [designs] index in
                    guard !designs.isEmpty else { return nil }
                    return onOpen(index % designs.count)
                }
                scene.onPhase = onPhase
                onScene?(scene)
            }
    }
}


