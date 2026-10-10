import CardUI
import SwiftUI

/// Tab root. Becomes a sidebar on iPad and in wide windows.
struct RootView: View {
    @State private var selection: DemoRoute = DemoRoute.fromLaunchArguments ?? .collection
    @State private var theme: CardTheme = .classic

    var body: some View {
        TabView(selection: $selection) {
            Tab(DemoRoute.collection.title, systemImage: DemoRoute.collection.symbol, value: .collection) {
                CollectionView(theme: $theme)
            }
            Tab(DemoRoute.effects.title, systemImage: DemoRoute.effects.symbol, value: .effects) {
                EffectsCatalogView()
            }
            Tab(DemoRoute.animations.title, systemImage: DemoRoute.animations.symbol, value: .animations) {
                AnimationsCatalogView()
            }
            Tab(DemoRoute.booster.title, systemImage: DemoRoute.booster.symbol, value: .booster) {
                BoosterDemoView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .cardTheme(theme)
        .tint(.yellow)
    }
}
