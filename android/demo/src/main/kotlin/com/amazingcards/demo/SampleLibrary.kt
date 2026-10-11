// Sample content, the same twelve cards as the iOS demo.
package com.amazingcards.demo

import com.amazingcards.cardkit.core.Artist
import com.amazingcards.cardkit.core.Attack
import com.amazingcards.cardkit.core.Card
import com.amazingcards.cardkit.core.CardArtwork
import com.amazingcards.cardkit.core.CardContent
import com.amazingcards.cardkit.core.CardFinish
import com.amazingcards.cardkit.core.CardNumber
import com.amazingcards.cardkit.core.CelestialKind
import com.amazingcards.cardkit.core.CelestialObject
import com.amazingcards.cardkit.core.Creature
import com.amazingcards.cardkit.core.CreatureElement
import com.amazingcards.cardkit.core.Painting
import com.amazingcards.cardkit.core.Rarity

object SampleLibrary {
    const val SET_NAME = "Amazing Set 1"

    val vanGogh = Card(
        id = "artist-van-gogh", title = "Vincent van Gogh", artwork = CardArtwork.Asset("vangogh_sticker"),
        content = CardContent.ArtistContent(Artist(
            born = "1853", died = "1890", nationality = "Dutch", movement = "Post-Impressionism",
            biography = "Painted some 2,100 works in a decade, most of them in the last two years of his life. Bold colour, dramatic brushwork and emotional honesty shaped twentieth-century art.",
            notableWorks = listOf("The Starry Night", "Sunflowers", "Wheatfield with Crows"),
            quote = "I dream my painting and I paint my dream.",
        )),
        rarity = Rarity.LEGENDARY, finish = CardFinish.GOLD, number = CardNumber(1, 12), setName = SET_NAME,
    )
    val starryNight = Card(
        id = "painting-starry-night", title = "The Starry Night", artwork = CardArtwork.Asset("starry_night"),
        content = CardContent.PaintingContent(Painting("Vincent van Gogh", "1889", "Oil on canvas", "73.7 × 92.1 cm", "MoMA, New York",
            "The view from the asylum window at Saint-Rémy, just before sunrise, with an imagined village and a swirling sky.")),
        rarity = Rarity.EPIC, finish = CardFinish.COSMOS, number = CardNumber(2, 12), setName = SET_NAME,
    )
    val sunflowers = Card(
        id = "painting-sunflowers", title = "Sunflowers", artwork = CardArtwork.Asset("sunflowers"),
        content = CardContent.PaintingContent(Painting("Vincent van Gogh", "1888", "Oil on canvas", "92.1 × 73 cm", "National Gallery, London",
            "Fourth version of the Arles series, painted to decorate Gauguin's room with yellow on yellow.")),
        rarity = Rarity.RARE, finish = CardFinish.HOLO, number = CardNumber(3, 12), setName = SET_NAME,
    )
    val wheatfield = Card(
        id = "painting-wheatfield", title = "Wheatfield with Crows", artwork = CardArtwork.Asset("wheatfield_crows"),
        content = CardContent.PaintingContent(Painting("Vincent van Gogh", "1890", "Oil on canvas", "50.5 × 103 cm", "Van Gogh Museum, Amsterdam",
            "A turbulent sky over a wheat field crossed by three paths, among his very last paintings.")),
        rarity = Rarity.UNCOMMON, finish = CardFinish.MATTE, number = CardNumber(4, 12), setName = SET_NAME,
    )
    val andromeda = Card(
        id = "celestial-andromeda", title = "Andromeda", artwork = CardArtwork.Asset("andromeda"),
        content = CardContent.CelestialContent(CelestialObject("M31 · NGC 224", CelestialKind.GALAXY, "Andromeda", "2.5 Mly", 3.4, "3° × 1°",
            "The nearest large galaxy to the Milky Way, visible to the naked eye and on a collision course with us in four billion years.")),
        rarity = Rarity.EPIC, finish = CardFinish.GALAXY, number = CardNumber(5, 12), setName = SET_NAME, credit = "Adam Evans",
    )
    val orion = Card(
        id = "celestial-orion", title = "Orion Nebula", artwork = CardArtwork.Asset("orion_nebula"),
        content = CardContent.CelestialContent(CelestialObject("M42 · NGC 1976", CelestialKind.NEBULA, "Orion", "1,344 ly", 4.0, "65′ × 60′",
            "A stellar nursery below Orion's belt, the closest region of massive star formation to Earth.")),
        rarity = Rarity.RARE, finish = CardFinish.PRISM, number = CardNumber(6, 12), setName = SET_NAME, credit = "NASA, ESA, Hubble",
    )
    val pillars = Card(
        id = "celestial-pillars", title = "Pillars of Creation", artwork = CardArtwork.Asset("pillars_of_creation"),
        content = CardContent.CelestialContent(CelestialObject("Eagle Nebula · M16", CelestialKind.NEBULA, "Serpens", "6,500 ly", 6.0, "7′",
            "Columns of cold gas and dust several light-years tall, sculpted by the ultraviolet light of nearby young stars.")),
        rarity = Rarity.LEGENDARY, finish = CardFinish.RAINBOW, number = CardNumber(7, 12), setName = SET_NAME, credit = "NASA, ESA, Hubble",
    )
    val saturn = Card(
        id = "celestial-saturn", title = "Saturn", artwork = CardArtwork.Asset("saturn"),
        content = CardContent.CelestialContent(CelestialObject("Planet VI", CelestialKind.PLANET, "Ecliptic", "1.4 billion km", 0.5, "18″",
            "The ringed giant seen at equinox by Cassini, rings edge-on to the Sun and casting a thin shadow.")),
        rarity = Rarity.COMMON, finish = CardFinish.MATTE, number = CardNumber(8, 12), setName = SET_NAME, credit = "NASA / JPL / SSI",
    )
    val vincentCreature = Card(
        id = "creature-vincent", title = "Vincent", artwork = CardArtwork.Asset("vangogh_sticker"),
        content = CardContent.CreatureContent(Creature(
            stage = "Basic", hitPoints = 90, element = CreatureElement.ART, species = "No. 1853   Painter   HT: 5′7″   WT: 140 lbs.",
            attacks = listOf(
                Attack("Impasto", listOf(CreatureElement.ART), 20, "Flip a coin. If heads, the Defending creature is now Dazzled."),
                Attack("Starry Swirl", listOf(CreatureElement.ART, CreatureElement.ART, CreatureElement.COLORLESS), 70, "Discard an Energy attached to Vincent."),
            ),
            weakness = CreatureElement.WATER, resistance = CreatureElement.PSYCHIC, retreatCost = 1,
            flavorText = "Paints through the night under a sky that never stops moving.",
        )),
        rarity = Rarity.RARE, finish = CardFinish.HOLO, number = CardNumber(9, 12), setName = SET_NAME, credit = "Wikimedia",
    )
    val saturnCreature = Card(
        id = "creature-saturn", title = "Saturnix", artwork = CardArtwork.Asset("saturn"),
        content = CardContent.CreatureContent(Creature(
            stage = "Stage 2", hitPoints = 210, element = CreatureElement.COSMIC, species = "No. 6   Ringed Giant   HT: 116,000 km",
            attacks = listOf(
                Attack("Ring Slash", listOf(CreatureElement.COSMIC, CreatureElement.COLORLESS), 60),
                Attack("Hexagon Storm", listOf(CreatureElement.COSMIC, CreatureElement.COSMIC, CreatureElement.COLORLESS), 150, "Your opponent's Active creature is now Confused."),
            ),
            weakness = CreatureElement.FIRE, retreatCost = 3, flavorText = "Its rings are younger than the dinosaurs.",
        )),
        rarity = Rarity.EPIC, finish = CardFinish.FULL_ART, number = CardNumber(10, 12), setName = SET_NAME, credit = "NASA / JPL",
    )
    val aurora = Card(
        id = "celestial-aurora", title = "Aurora Borealis", artwork = CardArtwork.Custom(CustomArtworks.AURORA),
        content = CardContent.CelestialContent(CelestialObject("Northern lights", CelestialKind.STAR, "Polar sky", "100 km up", null, null,
            "Solar wind meeting the upper atmosphere: curtains of green and violet light drawn live by a Canvas.")),
        rarity = Rarity.RARE, finish = CardFinish.GALAXY, number = CardNumber(11, 12), setName = SET_NAME, credit = "Drawn with Canvas",
    )
    val comet = Card(
        id = "celestial-comet", title = "Halley's Comet", artwork = CardArtwork.Custom(CustomArtworks.COMET),
        content = CardContent.CelestialContent(CelestialObject("1P/Halley", CelestialKind.COMET, "Varies", "0.6 au at perihelion", 2.1, null,
            "Back every 76 years. This one is painted with gradients and rendered into a picture.")),
        rarity = Rarity.UNCOMMON, finish = CardFinish.HOLO, number = CardNumber(12, 12), setName = SET_NAME, credit = "Drawn with Canvas",
    )

    val all: List<Card> = listOf(vanGogh, starryNight, sunflowers, wheatfield, andromeda, orion, pillars, saturn, vincentCreature, saturnCreature, aurora, comet)

    /** Pool for boosters: every card gets a matte common twin so commons exist for the three common slots. */
    val boosterPool: List<Card>
        get() = all + all.map { it.copy(id = it.id + "-print", rarity = Rarity.COMMON, finish = CardFinish.MATTE) }
}
