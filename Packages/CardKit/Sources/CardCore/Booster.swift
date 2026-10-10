import Foundation

/// A sealed booster: a few cards in reveal order (best card last).
public struct BoosterPack: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var cards: [Card]

    public init(id: UUID = UUID(), name: String, cards: [Card]) {
        self.id = id
        self.name = name
        self.cards = cards
    }

    /// Highest rarity in the pack, drives the reveal celebration.
    public var bestRarity: Rarity { cards.map(\.rarity).max() ?? .common }

    public var count: Int { cards.count }
}

/// One slot of a booster: which rarities may fill it.
public struct BoosterSlot: Hashable, Sendable, Codable {
    public enum Rule: Hashable, Sendable, Codable {
        /// Exactly this rarity.
        case exactly(Rarity)
        /// At least this rarity, picked by `Rarity.pullWeight`.
        case atLeast(Rarity)
        /// Any rarity, picked by `Rarity.pullWeight`.
        case wild
    }

    public var rule: Rule

    public init(_ rule: Rule) { self.rule = rule }

    func accepts(_ rarity: Rarity) -> Bool {
        switch rule {
        case .exactly(let wanted): rarity == wanted
        case .atLeast(let floor): rarity >= floor
        case .wild: true
        }
    }
}

/// Deterministic pack builder. Pure function of (pool, slots, rng) so that
/// tests and replays are reproducible.
public struct BoosterGenerator: Hashable, Sendable {
    public var slots: [BoosterSlot]

    /// Classic 5-card layout: 3 commons, 1 uncommon-or-better, 1 rare-or-better.
    public static let standard = BoosterGenerator(slots: [
        BoosterSlot(.exactly(.common)),
        BoosterSlot(.exactly(.common)),
        BoosterSlot(.exactly(.common)),
        BoosterSlot(.atLeast(.uncommon)),
        BoosterSlot(.atLeast(.rare)),
    ])

    public init(slots: [BoosterSlot]) {
        self.slots = slots
    }

    /// Builds a pack. Cards are unique inside a pack whenever the pool allows
    /// it; a slot that cannot be filled falls back to any card of the pool.
    /// Result is sorted by ascending rarity so the best card is revealed last.
    public func makePack(
        named name: String,
        from pool: [Card],
        using generator: inout some RandomNumberGenerator
    ) -> BoosterPack {
        guard !pool.isEmpty else { return BoosterPack(name: name, cards: []) }
        var picked: [Card] = []
        var usedIDs: Set<CardID> = []

        for slot in slots {
            var candidates = pool.filter { slot.accepts($0.rarity) && !usedIDs.contains($0.id) }
            if candidates.isEmpty { candidates = pool.filter { slot.accepts($0.rarity) } }
            if candidates.isEmpty { candidates = pool.filter { !usedIDs.contains($0.id) } }
            if candidates.isEmpty { candidates = pool }

            let chosen = Self.weightedPick(from: candidates, using: &generator)
            picked.append(chosen)
            usedIDs.insert(chosen.id)
        }

        let ordered = picked.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.rarity != rhs.element.rarity { return lhs.element.rarity < rhs.element.rarity }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        return BoosterPack(name: name, cards: ordered)
    }

    private static func weightedPick(
        from candidates: [Card],
        using generator: inout some RandomNumberGenerator
    ) -> Card {
        let total = candidates.reduce(0.0) { $0 + $1.rarity.pullWeight }
        var roll = Double.random(in: 0..<total, using: &generator)
        for card in candidates {
            roll -= card.rarity.pullWeight
            if roll < 0 { return card }
        }
        return candidates[candidates.count - 1]
    }
}

/// SplitMix64: tiny, fast, seedable generator for reproducible packs and tests.
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
