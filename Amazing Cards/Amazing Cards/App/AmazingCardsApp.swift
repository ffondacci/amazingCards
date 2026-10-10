import CardCore
import CardFX
import CardUI
import SwiftUI

@main
struct AmazingCardsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .task {
                    // Pre-compile every shader and decode the sample artwork
                    // so the first card never hitches.
                    let finishes = Set(SampleLibrary.all.compactMap(\.finish.holoStyle)).map { CardEffect.holo($0) }
                    async let shaders: Void = CardFXShaders.warmUp(first: CardFXShaders.packOpeningEffects + finishes)
                    let assets = SampleLibrary.all.compactMap { card -> String? in
                        if case .asset(let name) = card.artwork { return name }
                        return nil
                    }
                    async let images: Void = ArtworkLoader.shared.prewarm(assets: assets)
                    _ = await (shaders, images)
                }
        }
    }
}
