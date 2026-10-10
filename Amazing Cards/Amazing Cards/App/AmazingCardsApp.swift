import CardFX
import SwiftUI

@main
struct AmazingCardsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .task {
                    // Pre-compile every shader so the first card never hitches.
                    await CardFXShaders.warmUp()
                }
        }
    }
}
