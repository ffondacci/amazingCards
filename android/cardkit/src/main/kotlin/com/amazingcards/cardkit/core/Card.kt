// Pure models, mirrors of CardCore/Card.swift and CardContent.swift.
package com.amazingcards.cardkit.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** A colour in sRGB, framework-free like the Swift one. */
data class CardColor(val red: Double, val green: Double, val blue: Double) {
    constructor(hex: Long) : this(
        ((hex shr 16) and 0xFF) / 255.0,
        ((hex shr 8) and 0xFF) / 255.0,
        (hex and 0xFF) / 255.0,
    )

    val luminance: Double get() = 0.299 * red + 0.587 * green + 0.114 * blue

    /** Hue 0…1. */
    val hue: Double
        get() {
            val maxC = max(red, max(green, blue))
            val minC = min(red, min(green, blue))
            val delta = maxC - minC
            if (delta < 0.0001) return 0.0
            var h = when (maxC) {
                red -> (green - blue) / delta
                green -> 2 + (blue - red) / delta
                else -> 4 + (red - green) / delta
            }
            h /= 6
            if (h < 0) h += 1
            return h
        }

    val contrastingText: CardColor get() = if (luminance > 0.6) INK else PAPER

    /** ARGB int with the given alpha (0…1). */
    fun argb(alpha: Double = 1.0): Int {
        val a = (alpha.coerceIn(0.0, 1.0) * 255 + 0.5).toInt()
        val r = (red.coerceIn(0.0, 1.0) * 255 + 0.5).toInt()
        val g = (green.coerceIn(0.0, 1.0) * 255 + 0.5).toInt()
        val b = (blue.coerceIn(0.0, 1.0) * 255 + 0.5).toInt()
        return (a shl 24) or (r shl 16) or (g shl 8) or b
    }

    companion object {
        val GOLD = CardColor(0xE8B923)
        val SILVER = CardColor(0xC9D1DA)
        val INK = CardColor(0x14161C)
        val PAPER = CardColor(0xF4EFE6)
        val COBALT = CardColor(0x2B4C9B)
        val VERMILION = CardColor(0xE34234)
        val NEBULA = CardColor(0x7B4DFF)
        val AURORA = CardColor(0x3BE0C8)
    }
}

enum class Rarity(val displayName: String, val color: CardColor, val pullWeight: Double) {
    COMMON("Common", CardColor(0x9AA0A6), 50.0),
    UNCOMMON("Uncommon", CardColor(0x4CC2A8), 28.0),
    RARE("Rare", CardColor(0x4D8DF0), 14.0),
    EPIC("Epic", CardColor(0xB45CFF), 6.0),
    LEGENDARY("Legendary", CardColor(0xF2B632), 2.0);
}

enum class CardFinish(val displayName: String) {
    MATTE("Matte"), HOLO("Holo"), REVERSE_HOLO("Reverse holo"), COSMOS("Cosmos"), GALAXY("Galaxy"),
    RAINBOW("Rainbow"), GOLD("Gold"), AMAZING("Amazing"), RADIANT("Radiant"), PRISM("Prism"),
    PEARL("Pearl"), BRUSHED_METAL("Brushed metal"), FULL_ART("Full art"), INTERFERENCE("Interference");

    val isFoil: Boolean get() = this != MATTE
}

/** Where the picture of a card comes from. */
sealed class CardArtwork {
    /** A drawable resource of the app, by name. */
    data class Asset(val name: String) : CardArtwork()
    /** A picture the app draws itself, found by key in the artwork provider. */
    data class Custom(val key: String) : CardArtwork()
    data object None : CardArtwork()
}

data class CardNumber(val index: Int, val total: Int) {
    val formatted: String
        get() {
            val width = total.toString().length
            return index.toString().padStart(width, '0') + "/" + total
        }
}

enum class CardTemplate { CREATURE, ARTIST, PAINTING, CELESTIAL }

enum class CreatureElement(val color: CardColor) {
    FIRE(CardColor(0xE8542F)), WATER(CardColor(0x3D8FE0)), GRASS(CardColor(0x5BB543)), ELECTRIC(CardColor(0xF2C530)),
    PSYCHIC(CardColor(0x9B59B6)), ROCK(CardColor(0xA3783E)), METAL(CardColor(0x9AA7B2)), COSMIC(CardColor(0x4B3FBF)),
    ART(CardColor(0xD9534F)), COLORLESS(CardColor(0xD6D6D6));

    val displayName: String get() = name.lowercase().replaceFirstChar { it.uppercase() }
}

data class Attack(val name: String, val cost: List<CreatureElement>, val damage: Int? = null, val text: String? = null)

data class Creature(
    val stage: String = "Basic",
    val hitPoints: Int,
    val element: CreatureElement,
    val species: String,
    val attacks: List<Attack>,
    val weakness: CreatureElement? = null,
    val resistance: CreatureElement? = null,
    val retreatCost: Int = 1,
    val flavorText: String? = null,
)

data class Artist(
    val born: String,
    val died: String? = null,
    val nationality: String,
    val movement: String,
    val biography: String,
    val notableWorks: List<String> = emptyList(),
    val quote: String? = null,
) {
    val lifespan: String get() = if (died != null) "$born – $died" else "$born –"
}

data class Painting(
    val artist: String,
    val year: String,
    val medium: String,
    val dimensions: String? = null,
    val location: String? = null,
    val description: String,
)

enum class CelestialKind(val color: CardColor) {
    GALAXY(CardColor(0x8E7CFF)), NEBULA(CardColor(0xFF6FB5)), PLANET(CardColor(0xF0B35B)), STAR(CardColor(0xFFE28A)),
    CLUSTER(CardColor(0x7FD4FF)), MOON(CardColor(0xC8CDD6)), COMET(CardColor(0x9EF5E3));

    val displayName: String get() = name.lowercase().replaceFirstChar { it.uppercase() }
}

data class CelestialObject(
    val designation: String,
    val kind: CelestialKind,
    val constellation: String,
    val distance: String,
    val apparentMagnitude: Double? = null,
    val apparentSize: String? = null,
    val description: String,
)

sealed class CardContent {
    data class CreatureContent(val creature: Creature) : CardContent()
    data class ArtistContent(val artist: Artist) : CardContent()
    data class PaintingContent(val painting: Painting) : CardContent()
    data class CelestialContent(val obj: CelestialObject) : CardContent()

    val template: CardTemplate
        get() = when (this) {
            is CreatureContent -> CardTemplate.CREATURE
            is ArtistContent -> CardTemplate.ARTIST
            is PaintingContent -> CardTemplate.PAINTING
            is CelestialContent -> CardTemplate.CELESTIAL
        }
}

/** A collectible card: what it shows and how it is printed. */
data class Card(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val artwork: CardArtwork,
    val content: CardContent,
    val rarity: Rarity = Rarity.COMMON,
    val finish: CardFinish = CardFinish.MATTE,
    val number: CardNumber? = null,
    val setName: String? = null,
    val credit: String? = null,
    val accent: CardColor? = null,
) {
    val template: CardTemplate get() = content.template
    val isFoil: Boolean get() = finish.isFoil

    /** Accent colour used by the template (explicit, else derived from the content). */
    val resolvedAccent: CardColor
        get() = accent ?: when (val c = content) {
            is CardContent.CreatureContent -> c.creature.element.color
            is CardContent.ArtistContent -> CardColor.VERMILION
            is CardContent.PaintingContent -> CardColor.COBALT
            is CardContent.CelestialContent -> c.obj.kind.color
        }
}

internal fun fmix(a: Double, b: Double, t: Double) = a + (b - a) * t
internal fun absd(x: Double) = abs(x)
