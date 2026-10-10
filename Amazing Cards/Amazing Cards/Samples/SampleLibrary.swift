import CardCore

/// Sample content: one artist, three paintings, four celestial objects and
/// two playful creature cards. Images are public domain (Wikimedia Commons).
enum SampleLibrary {
    static let setName = "Amazing Set 1"

    static let vanGogh = Card(
        id: "artist-van-gogh",
        title: "Vincent van Gogh",
        artwork: .asset("vangogh_sticker"),
        content: .artist(Artist(
            born: "1853",
            died: "1890",
            nationality: "Dutch",
            movement: "Post-Impressionism",
            biography: "Painted some 2,100 works in a decade, most of them in the last two years of his life. Bold colour, dramatic brushwork and emotional honesty shaped twentieth-century art.",
            notableWorks: ["The Starry Night", "Sunflowers", "Wheatfield with Crows"],
            quote: "I dream my painting and I paint my dream."
        )),
        rarity: .legendary,
        finish: .gold,
        number: CardNumber(1, of: 10),
        setName: setName
    )

    static let starryNight = Card(
        id: "painting-starry-night",
        title: "The Starry Night",
        artwork: .asset("starry_night"),
        content: .painting(Painting(
            artist: "Vincent van Gogh",
            year: "1889",
            medium: "Oil on canvas",
            dimensions: "73.7 × 92.1 cm",
            location: "MoMA, New York",
            description: "The view from the asylum window at Saint-Rémy, just before sunrise, with an imagined village and a swirling sky."
        )),
        rarity: .epic,
        finish: .cosmos,
        number: CardNumber(2, of: 10),
        setName: setName
    )

    static let sunflowers = Card(
        id: "painting-sunflowers",
        title: "Sunflowers",
        artwork: .asset("sunflowers"),
        content: .painting(Painting(
            artist: "Vincent van Gogh",
            year: "1888",
            medium: "Oil on canvas",
            dimensions: "92.1 × 73 cm",
            location: "National Gallery, London",
            description: "Fourth version of the Arles series, painted to decorate Gauguin's room with yellow on yellow."
        )),
        rarity: .rare,
        finish: .holo,
        number: CardNumber(3, of: 10),
        setName: setName
    )

    static let wheatfield = Card(
        id: "painting-wheatfield",
        title: "Wheatfield with Crows",
        artwork: .asset("wheatfield_crows"),
        content: .painting(Painting(
            artist: "Vincent van Gogh",
            year: "1890",
            medium: "Oil on canvas",
            dimensions: "50.5 × 103 cm",
            location: "Van Gogh Museum, Amsterdam",
            description: "A turbulent sky over a wheat field crossed by three paths, among his very last paintings."
        )),
        rarity: .uncommon,
        finish: .matte,
        number: CardNumber(4, of: 10),
        setName: setName
    )

    static let andromeda = Card(
        id: "celestial-andromeda",
        title: "Andromeda",
        artwork: .asset("andromeda"),
        content: .celestial(CelestialObject(
            designation: "M31 · NGC 224",
            kind: .galaxy,
            constellation: "Andromeda",
            distance: "2.5 Mly",
            apparentMagnitude: 3.4,
            apparentSize: "3° × 1°",
            description: "The nearest large galaxy to the Milky Way, visible to the naked eye and on a collision course with us in four billion years."
        )),
        rarity: .epic,
        finish: .galaxy,
        number: CardNumber(5, of: 10),
        setName: setName,
        credit: "Adam Evans"
    )

    static let orion = Card(
        id: "celestial-orion",
        title: "Orion Nebula",
        artwork: .asset("orion_nebula"),
        content: .celestial(CelestialObject(
            designation: "M42 · NGC 1976",
            kind: .nebula,
            constellation: "Orion",
            distance: "1,344 ly",
            apparentMagnitude: 4.0,
            apparentSize: "65′ × 60′",
            description: "A stellar nursery below Orion's belt, the closest region of massive star formation to Earth."
        )),
        rarity: .rare,
        finish: .prism,
        number: CardNumber(6, of: 10),
        setName: setName,
        credit: "NASA, ESA, Hubble"
    )

    static let pillars = Card(
        id: "celestial-pillars",
        title: "Pillars of Creation",
        artwork: .asset("pillars_of_creation"),
        content: .celestial(CelestialObject(
            designation: "Eagle Nebula · M16",
            kind: .nebula,
            constellation: "Serpens",
            distance: "6,500 ly",
            apparentMagnitude: 6.0,
            apparentSize: "7′",
            description: "Columns of cold gas and dust several light-years tall, sculpted by the ultraviolet light of nearby young stars."
        )),
        rarity: .legendary,
        finish: .rainbow,
        number: CardNumber(7, of: 10),
        setName: setName,
        credit: "NASA, ESA, Hubble"
    )

    static let saturn = Card(
        id: "celestial-saturn",
        title: "Saturn",
        artwork: .asset("saturn"),
        content: .celestial(CelestialObject(
            designation: "Planet VI",
            kind: .planet,
            constellation: "Ecliptic",
            distance: "1.4 billion km",
            apparentMagnitude: 0.5,
            apparentSize: "18″",
            description: "The ringed giant seen at equinox by Cassini, rings edge-on to the Sun and casting a thin shadow."
        )),
        rarity: .common,
        finish: .matte,
        number: CardNumber(8, of: 10),
        setName: setName,
        credit: "NASA / JPL / SSI"
    )

    static let vincentCreature = Card(
        id: "creature-vincent",
        title: "Vincent",
        artwork: .asset("vangogh_sticker"),
        content: .creature(Creature(
            stage: "Basic",
            hitPoints: 90,
            element: .art,
            species: "No. 1853   Painter   HT: 5′7″   WT: 140 lbs.",
            attacks: [
                Attack(name: "Impasto", cost: [.art], damage: 20, text: "Flip a coin. If heads, the Defending creature is now Dazzled."),
                Attack(name: "Starry Swirl", cost: [.art, .art, .colorless], damage: 70, text: "Discard an Energy attached to Vincent."),
            ],
            weakness: .water,
            resistance: .psychic,
            retreatCost: 1,
            flavorText: "Paints through the night under a sky that never stops moving."
        )),
        rarity: .rare,
        finish: .holo,
        number: CardNumber(9, of: 10),
        setName: setName,
        credit: "Wikimedia"
    )

    static let saturnCreature = Card(
        id: "creature-saturn",
        title: "Saturnix",
        artwork: .asset("saturn"),
        content: .creature(Creature(
            stage: "Stage 2",
            hitPoints: 210,
            element: .cosmic,
            species: "No. 6   Ringed Giant   HT: 116,000 km",
            attacks: [
                Attack(name: "Ring Slash", cost: [.cosmic, .colorless], damage: 60),
                Attack(name: "Hexagon Storm", cost: [.cosmic, .cosmic, .colorless], damage: 150, text: "Your opponent's Active creature is now Confused."),
            ],
            weakness: .fire,
            retreatCost: 3,
            flavorText: "Its rings are younger than the dinosaurs."
        )),
        rarity: .epic,
        finish: .fullArt,
        number: CardNumber(10, of: 10),
        setName: setName,
        credit: "NASA / JPL"
    )

    static let all: [Card] = [
        vanGogh, starryNight, sunflowers, wheatfield,
        andromeda, orion, pillars, saturn,
        vincentCreature, saturnCreature,
    ]

    static let set = CardSet(id: "amazing-set-1", name: setName, cards: all)

    /// Pool for boosters: every card in every rarity bucket gets a matte
    /// twin so commons exist for the three common slots.
    static var boosterPool: [Card] {
        all + all.map { card in
            var twin = card
            twin.id = CardID(card.id.rawValue + "-print")
            twin.rarity = .common
            twin.finish = .matte
            return twin
        }
    }
}
