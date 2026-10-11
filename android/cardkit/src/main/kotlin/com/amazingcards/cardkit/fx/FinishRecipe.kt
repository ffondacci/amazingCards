// Which passes a finish applies, split by region of a framed card (FinishRecipe.swift).
package com.amazingcards.cardkit.fx

import com.amazingcards.cardkit.core.CardFinish
import com.amazingcards.cardkit.core.CardTemplate

data class FinishRecipe(val artwork: List<CardEffect> = emptyList(), val frame: List<CardEffect> = emptyList(), val fullCard: List<CardEffect> = emptyList()) {
    val isTimeDriven: Boolean get() = (artwork + frame + fullCard).any { it.isTimeDriven }

    companion object {
        val NONE = FinishRecipe()

        fun recipe(finish: CardFinish, template: CardTemplate): FinishRecipe {
            val glare = CardEffect.Glare(intensity = 0.3f, radius = 0.95f)
            val style = finish.holoStyle ?: return FinishRecipe(fullCard = listOf(CardEffect.Glare(intensity = 0.35f, radius = 1f)))
            val foil = CardEffect.Holo(style)
            val hasBorder = template == CardTemplate.CREATURE || template == CardTemplate.ARTIST
            val region = if (hasBorder) finish.region else FinishRegion.FULL_CARD
            return when (region) {
                FinishRegion.ARTWORK -> FinishRecipe(artwork = listOf(foil, glare), fullCard = listOf(CardEffect.Glare(0.2f, 1.1f)))
                FinishRegion.FRAME -> FinishRecipe(artwork = listOf(glare), frame = listOf(foil), fullCard = listOf(CardEffect.Glare(0.2f, 1.1f)))
                FinishRegion.FULL_CARD -> FinishRecipe(fullCard = listOf(foil, glare))
            }
        }
    }
}

enum class FinishRegion { ARTWORK, FRAME, FULL_CARD }

val CardFinish.holoStyle: HoloStyle?
    get() = when (this) {
        CardFinish.MATTE -> null
        CardFinish.HOLO -> HoloStyle.REGULAR
        CardFinish.REVERSE_HOLO -> HoloStyle.REVERSE_HOLO
        CardFinish.COSMOS -> HoloStyle.COSMOS
        CardFinish.GALAXY -> HoloStyle.GALAXY
        CardFinish.RAINBOW -> HoloStyle.RAINBOW
        CardFinish.GOLD -> HoloStyle.GOLD
        CardFinish.AMAZING -> HoloStyle.AMAZING
        CardFinish.RADIANT -> HoloStyle.RADIANT
        CardFinish.PRISM -> HoloStyle.PRISM
        CardFinish.PEARL -> HoloStyle.PEARL
        CardFinish.BRUSHED_METAL -> HoloStyle.BRUSHED_METAL
        CardFinish.FULL_ART -> HoloStyle.FULL_ART
        CardFinish.INTERFERENCE -> HoloStyle.INTERFERENCE
    }

/** Where the foil is printed on framed templates. */
val CardFinish.region: FinishRegion
    get() = when (this) {
        CardFinish.MATTE -> FinishRegion.FULL_CARD
        CardFinish.HOLO, CardFinish.COSMOS, CardFinish.AMAZING -> FinishRegion.ARTWORK
        CardFinish.REVERSE_HOLO -> FinishRegion.FRAME
        else -> FinishRegion.FULL_CARD
    }
