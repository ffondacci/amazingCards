import CardCore
import CardFX
import CardUI
import SwiftUI

/// Invisible view that exercises everything the pack opening uses on its
/// first frame: the whole `PackOpeningView` with its deck, rasterized pack,
/// star field, fonts and shader pipelines, plus one torn frame for the curl
/// and sparks shaders. First instantiation of these view types and Metal
/// pipelines is what stalls an otherwise smooth first opening.
///
/// Show it once at launch, behind the UI:
/// ```swift
/// RootView().background { PackWarmUpView(design: someDesign, sampleCards: cards) }
/// ```
public struct PackWarmUpView: View {
    public var design: PackDesign
    public var sampleCards: [Card]

    @State private var tear = TearState()
    @State private var done = false

    public init(design: PackDesign, sampleCards: [Card] = []) {
        self.design = design
        self.sampleCards = sampleCards
    }

    public var body: some View {
        if !done {
            ZStack {
                PackOpeningView(
                    pack: BoosterPack(name: "warm-up", cards: Array(sampleCards.prefix(3))),
                    design: design,
                    playsSound: false
                )
                TornPackView(
                    design: design,
                    width: 200,
                    height: 200 / PackDesign.aspectRatio,
                    tear: tear,
                    roughness: 5,
                    flyAway: false,
                    bodyOffsetY: 0,
                    bodyOpacity: 1
                )
            }
            .frame(width: 320, height: 560)
            .opacity(0.02)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                // One frame with the strip torn exercises the curl and sparks shaders.
                try? await Task.sleep(for: .milliseconds(150))
                tear.viewSize = CGSize(width: 200, height: 200 / PackDesign.aspectRatio)
                tear.origin = CGPoint(x: 0, y: 30)
                tear.direction = CGPoint(x: 1, y: 0)
                tear.tip = CGPoint(x: 90, y: 30)
                tear.isActive = true
                try? await Task.sleep(for: .milliseconds(1200))
                tear.isActive = false
                done = true
            }
        }
    }
}
