// The four wrappers of the demo, the same as the iOS booster screen.
package com.amazingcards.demo

import com.amazingcards.cardkit.core.CardArtwork
import com.amazingcards.cardkit.core.CardColor
import com.amazingcards.cardkit.core.PackDesign
import com.amazingcards.cardkit.core.PackEmblem

object PackDesigns {
    val all = listOf(
        PackDesign(title = "Masterpieces", subtitle = "Van Gogh", setCode = "S1", cover = CardArtwork.Asset("starry_night"),
            topColor = CardColor(0x1B2A6B), bottomColor = CardColor(0x0B1030), accent = CardColor.GOLD, foilHue = 0.6, emblem = PackEmblem.PALETTE),
        PackDesign(title = "Deep Sky", subtitle = "Observatory", setCode = "S1", cover = CardArtwork.Asset("pillars_of_creation"),
            topColor = CardColor(0x2A0845), bottomColor = CardColor(0x05020F), accent = CardColor.AURORA, foilHue = 0.8, emblem = PackEmblem.MOON_STARS),
        PackDesign(title = "Aurora", subtitle = "Drawn with Canvas", setCode = "S1", cover = CardArtwork.Custom(CustomArtworks.AURORA),
            topColor = CardColor(0x063D3A), bottomColor = CardColor(0x02110F), accent = CardColor(0x5CFFB0), foilHue = 0.45, emblem = PackEmblem.SPARKLES),
        PackDesign(title = "Amazing", subtitle = "Series 1", setCode = "S1", cover = CardArtwork.Asset("saturn"),
            topColor = CardColor(0xB3121F), bottomColor = CardColor(0x3A0710), accent = CardColor(0xFFC53D), foilHue = 0.02, emblem = PackEmblem.SPARKLES),
    )
}
