import CardFX
import CoreGraphics
import Testing

@Suite("Shader catalog")
struct CardEffectTests {
    @Test("Every holo style has a showcase entry")
    func showcaseCoversHoloStyles() {
        let styles = CardEffect.showcase.compactMap { effect -> HoloStyle? in
            if case .holo(let style, _) = effect { return style }
            return nil
        }
        #expect(Set(styles) == Set(HoloStyle.allCases))
    }

    @Test("Showcase names are unique")
    func uniqueNames() {
        let names = CardEffect.showcase.map(\.displayName)
        #expect(Set(names).count == names.count)
    }

    @Test("Shaders build without touching the GPU")
    func shadersBuild() {
        let motion = CardMotion(tilt: CGPoint(x: 0.3, y: -0.2), pointer: CGPoint(x: 0.4, y: 0.6), time: 1)
        for effect in CardEffect.showcase {
            _ = effect.shader(motion: motion, size: CGSize(width: 300, height: 420))
        }
    }

    @Test("Tear edge noise is bounded")
    func tearNoiseBounded() {
        for i in 0..<2000 {
            let v = TearShader.edgeOffset(at: Double(i) * 0.37)
            #expect(abs(v) <= 1.0)
        }
    }

    @Test("Distance from centre")
    func distance() {
        #expect(CardMotion().distanceFromCenter == 0)
        let corner = CardMotion(pointer: CGPoint(x: 1, y: 1))
        #expect(abs(corner.distanceFromCenter - 1) < 0.0001)
    }
}
