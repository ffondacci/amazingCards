// Everything that makes a booster look like itself, a mirror of PackDesign.swift.
package com.amazingcards.cardkit.core

enum class PackEmblem { SPARKLES, PALETTE, MOON_STARS }

data class PackDesign(
    val title: String,
    val subtitle: String? = null,
    val brand: String = "AMAZING CARDS",
    val setCode: String? = null,
    val cover: CardArtwork,
    val topColor: CardColor,
    val bottomColor: CardColor,
    val accent: CardColor = CardColor.GOLD,
    val foilHue: Double = 0.62,
    val prismIntensity: Double = 0.2,
    val emblem: PackEmblem = PackEmblem.SPARKLES,
    val cardCount: Int = 5,
    val stripFraction: Float = 0.175f,
    val bottomFraction: Float = 0.06f,
) {
    companion object {
        /** Width over height of the pouch, the same as the 3D stage. */
        const val ASPECT_RATIO = 1f / 1.86f
    }
}
