// Booster packs and the deterministic generator, mirrors of CardCore/Booster.swift.
package com.amazingcards.cardkit.core

data class BoosterPack(val name: String, val cards: List<Card>) {
    val bestRarity: Rarity get() = cards.maxOfOrNull { it.rarity } ?: Rarity.COMMON
    val count: Int get() = cards.size
}

/** One slot of a booster: which rarities may fill it. */
sealed class BoosterSlot {
    data class Exactly(val rarity: Rarity) : BoosterSlot()
    data class AtLeast(val floor: Rarity) : BoosterSlot()
    data object Wild : BoosterSlot()

    fun accepts(rarity: Rarity): Boolean = when (this) {
        is Exactly -> rarity == this.rarity
        is AtLeast -> rarity >= floor
        Wild -> true
    }
}

/** SplitMix64, the same stream as the Swift generator for a given seed. */
class SeededRandom(private var state: ULong) {
    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }

    /** Uniform double in [0, bound). */
    fun nextDouble(bound: Double): Double = (next() shr 11).toDouble() / (1L shl 53).toDouble() * bound
}

class BoosterGenerator(val slots: List<BoosterSlot>) {
    fun makePack(name: String, pool: List<Card>, random: SeededRandom): BoosterPack {
        if (pool.isEmpty()) return BoosterPack(name, emptyList())
        val picked = ArrayList<Card>()
        val used = HashSet<String>()
        for (slot in slots) {
            var candidates = pool.filter { slot.accepts(it.rarity) && it.id !in used }
            if (candidates.isEmpty()) candidates = pool.filter { slot.accepts(it.rarity) }
            if (candidates.isEmpty()) candidates = pool.filter { it.id !in used }
            if (candidates.isEmpty()) candidates = pool
            val chosen = weightedPick(candidates, random)
            picked.add(chosen)
            used.add(chosen.id)
        }
        val ordered = picked.withIndex().sortedWith(compareBy({ it.value.rarity }, { it.index })).map { it.value }
        return BoosterPack(name, ordered)
    }

    private fun weightedPick(candidates: List<Card>, random: SeededRandom): Card {
        val total = candidates.sumOf { it.rarity.pullWeight }
        var roll = random.nextDouble(total)
        for (card in candidates) {
            roll -= card.rarity.pullWeight
            if (roll < 0) return card
        }
        return candidates.last()
    }

    companion object {
        /** Classic 5-card layout: 3 commons, 1 uncommon-or-better, 1 rare-or-better. */
        val STANDARD = BoosterGenerator(
            listOf(
                BoosterSlot.Exactly(Rarity.COMMON), BoosterSlot.Exactly(Rarity.COMMON), BoosterSlot.Exactly(Rarity.COMMON),
                BoosterSlot.AtLeast(Rarity.UNCOMMON), BoosterSlot.AtLeast(Rarity.RARE),
            )
        )
    }
}
