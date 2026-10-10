import CardCore
import Testing

@Suite("Booster generation")
struct BoosterGeneratorTests {
    private static func pool() -> [Card] {
        var cards: [Card] = []
        for (index, rarity) in Rarity.allCases.enumerated() {
            for n in 0..<4 {
                cards.append(
                    Card(
                        id: CardID("\(rarity.rawValue)-\(n)"),
                        title: "\(rarity.displayName) \(n)",
                        artwork: .none,
                        content: .painting(Painting(artist: "A", year: "1900", medium: "Oil", description: "")),
                        rarity: rarity,
                        finish: rarity.defaultFinish,
                        number: CardNumber(index * 4 + n + 1, of: 20)
                    )
                )
            }
        }
        return cards
    }

    @Test("Standard pack has five cards, best card last")
    func standardPack() {
        var rng = SeededRandomNumberGenerator(seed: 42)
        let pack = BoosterGenerator.standard.makePack(named: "Test", from: Self.pool(), using: &rng)
        #expect(pack.count == 5)
        #expect(pack.cards.last?.rarity == pack.bestRarity)
        #expect(pack.bestRarity >= .rare)
        let rarities = pack.cards.map(\.rarity)
        #expect(rarities == rarities.sorted())
    }

    @Test("Same seed, same pack")
    func deterministic() {
        var a = SeededRandomNumberGenerator(seed: 7)
        var b = SeededRandomNumberGenerator(seed: 7)
        let packA = BoosterGenerator.standard.makePack(named: "A", from: Self.pool(), using: &a)
        let packB = BoosterGenerator.standard.makePack(named: "B", from: Self.pool(), using: &b)
        #expect(packA.cards.map(\.id) == packB.cards.map(\.id))
    }

    @Test("Cards are unique inside a pack when the pool allows it")
    func uniqueness() {
        var rng = SeededRandomNumberGenerator(seed: 1)
        for _ in 0..<50 {
            let pack = BoosterGenerator.standard.makePack(named: "U", from: Self.pool(), using: &rng)
            #expect(Set(pack.cards.map(\.id)).count == pack.count)
        }
    }

    @Test("Empty pool yields an empty pack instead of crashing")
    func emptyPool() {
        var rng = SeededRandomNumberGenerator(seed: 3)
        let pack = BoosterGenerator.standard.makePack(named: "E", from: [], using: &rng)
        #expect(pack.cards.isEmpty)
    }

    @Test("Slot without matching rarity falls back to the pool")
    func fallback() {
        var rng = SeededRandomNumberGenerator(seed: 9)
        let commonsOnly = Self.pool().filter { $0.rarity == .common }
        let pack = BoosterGenerator.standard.makePack(named: "F", from: commonsOnly, using: &rng)
        #expect(pack.count == 5)
    }
}

@Suite("Models")
struct ModelTests {
    @Test("Card number is zero padded")
    func numberFormatting() {
        #expect(CardNumber(7, of: 151).formatted == "007/151")
        #expect(CardNumber(12, of: 12).formatted == "12/12")
    }

    @Test("Finish regions on framed and borderless templates")
    func finishRegions() {
        #expect(CardFinish.holo.region == .artwork)
        #expect(CardFinish.reverseHolo.region == .frame)
        #expect(CardFinish.gold.region == .fullCard)
        #expect(CardTemplate.painting.hasBorder == false)
        #expect(CardTemplate.artist.hasBorder == true)
    }

    @Test("Cards survive a JSON round trip")
    func codable() throws {
        let card = Card(
            id: "vangogh",
            title: "Vincent van Gogh",
            artwork: .asset("vangogh_sticker"),
            content: .artist(Artist(born: "1853", died: "1890", nationality: "Dutch", movement: "Post-Impressionism", biography: "…")),
            rarity: .legendary,
            finish: .gold
        )
        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(Card.self, from: data)
        #expect(decoded == card)
    }
}

import Foundation
