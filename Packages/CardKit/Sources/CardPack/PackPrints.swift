import CardCore
import CardStage
import CardUI
import CoreGraphics
import SwiftUI

/// Renders the printed sides of a pack design into pictures for the 3D
/// stage: the front from `BoosterPackView`, the back from `PackBackView`,
/// both in the pouch proportions. Runs on the main actor (SwiftUI renders
/// there) and caches by design.
@MainActor
public final class PackPrints {
    /// Pixel width of a print; the height follows the pouch ratio.
    public var width: Int
    private var cache: [PackDesign: PackSkin] = [:]

    public init(width: Int = 1024) {
        self.width = width
    }

    /// Loads the cover of every design first, so the prints are not blank.
    public func prepare(_ designs: [PackDesign]) async {
        var names: [String] = []
        for design in designs {
            if case .asset(let name) = design.cover { names.append(name) }
        }
        await ArtworkLoader.shared.prewarm(assets: names)
    }

    /// The skin of a design, rendered on first use.
    public func skin(for design: PackDesign) -> PackSkin? {
        if let cached = cache[design] { return cached }
        let size = CGSize(width: CGFloat(width), height: CGFloat(width) / PackDesign.aspectRatio)
        guard let front = render(BoosterPackView(design: design, forPrint: true), size: size),
              let back = render(PackBackView(design: design), size: size)
        else { return nil }
        let frontMask = render(BoosterPackView(design: design, asMask: true), size: size)
        let backMask = render(PackBackView(design: design, asMask: true), size: size)
        let skin = PackSkin(id: "\(design.hashValue)", front: front, back: back, frontMask: frontMask, backMask: backMask)
        cache[design] = skin
        return skin
    }

    /// Loads the artwork of cards that may be dealt, so their pictures render whole.
    public func prepareCards(_ cards: [Card]) async {
        var names: [String] = []
        for card in cards {
            if case .asset(let name) = card.artwork { names.append(name) }
        }
        await ArtworkLoader.shared.prewarm(assets: names)
    }

    /// Pictures of the cards of one pack, front and back, with a foil
    /// mask for the foil finishes. The stage lights them itself, so the
    /// front is drawn without its own finish.
    public func cardSkins(for cards: [Card], width: Int = 640) -> [CardSkin] {
        let size = CGSize(width: CGFloat(width), height: CGFloat(width) / CardMetrics.aspectRatio)
        guard let back = cardBack(size: size) else { return [] }
        return cards.compactMap { cardSkin($0, back: back, size: size, width: width) }
    }

    /// Same, one card per run of the loop so the stage keeps its frame rate.
    public func cardSkins(for cards: [Card], width: Int = 640) async -> [CardSkin] {
        let size = CGSize(width: CGFloat(width), height: CGFloat(width) / CardMetrics.aspectRatio)
        guard let back = cardBack(size: size) else { return [] }
        var skins: [CardSkin] = []
        for card in cards {
            if Task.isCancelled { return [] }
            if let skin = cardSkin(card, back: back, size: size, width: width) { skins.append(skin) }
            await Task.yield()
        }
        return skins
    }

    private var backCache: [Int: CGImage] = [:]

    private func cardBack(size: CGSize) -> CGImage? {
        if let cached = backCache[Int(size.width)] { return cached }
        let back = render(CardBackView(), size: size)
        backCache[Int(size.width)] = back
        return back
    }

    private func cardSkin(_ card: Card, back: CGImage, size: CGSize, width: Int) -> CardSkin? {
        guard let front = render(CardView(card: card, showsFinish: false), size: size) else { return nil }
        let mask = card.isFoil ? render(PackPrintKind.maskColor(foil: 0.6, holo: 0.8, matte: 0), size: size) : nil
        return CardSkin(id: "\(card.id)-\(width)", front: front, back: back, mask: mask)
    }

    private func render<Content: View>(_ content: Content, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.cgImage
    }
}
