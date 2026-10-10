# Amazing Cards

Building blocks for a collectible-card app: card models, Metal holographic
effects, card templates, interactive tilt, flip, and a booster-pack opening
flow. Everything lives in the `CardKit` Swift package (`Packages/CardKit`);
the `Amazing Cards` Xcode project is a demo that catalogs every brick.

Swift 6, SwiftUI, Metal (SwiftUI shaders). iOS 26+. See `CLAUDE.md` for the
engineering guidelines.

## Package layout

| Product | What it contains |
|---|---|
| `CardCore` | Pure models: `Card`, `CardContent` (creature / artist / painting / celestial), `Rarity`, `CardFinish`, `BoosterPack`, `BoosterGenerator`, `SeededRandomNumberGenerator`. No UI. |
| `CardFX` | Metal shaders + SwiftUI modifiers: `CardEffect`, `HoloStyle`, `cardMotion(...)`, `CardMotionStage`, `TiltTransform`, `DeviceMotionSource`, animatable `cardSweep` / `cardDissolve` / `cardRipple`, `CardFXShaders.warmUp()`. |
| `CardUI` | `CardView` (picks a template per content), `CardMetrics` (size-relative layout), `FinishRecipe`, `CardTheme`, `CardBackView`, `FlippableCardView`, `InteractiveCardView`, `CardFanView`, `ArtworkView` + `ArtworkLoader` actor, `cardIdleFloat`, `cardShake`, `.cardDissolve()` transition. |
| `CardPack` | `PackDesign` (pocket-pack layout: top band, seam, full-bleed cover, bottom band), `BoosterPackView`, `PackCarouselView`, `tearable(...)` + `TearState` + `TornEdgeShape`, `TornPackView` (strip curls progressively with `ck_curl`), `CardSwipeStack`, `PackOpeningView` + `PackOpeningModel`. |

Dependency direction: `CardCore ← CardFX ← CardUI ← CardPack`.

## Effects (`CardEffect`)

Foil styles rendered by one shader (`ck_holo`, `HoloStyle`): regular holo,
cosmos, reverse holo, galaxy, rainbow, gold, amazing, radiant, prism, pearl,
brushed metal, full art, interference.

Overlays and generators: glare, sparkle, light sweep, shimmer, holo paper,
foil wrapper, star field, nebula (4 palettes), burst, sparks, chromatic
split, dissolve. Geometry: tear (`ck_tear`), strip curl (`ck_curl`), ripple (`ck_ripple`).

All effects read `CardMotion` (tilt, pointer, time) from the environment.

```swift
CardMotionStage {                       // drag to tilt, gyroscope, shadow
    CardView(card: card)                // template + finish recipe
}

artwork
    .cardEffect(.holo(.cosmos))
    .cardEffect(.glare())
```

## Card templates

| Template | Frame | Used for |
|---|---|---|
| `creature` | bordered, artwork window, attacks, footer | classic trading card |
| `artist` | bordered, sticker portrait, biography | an artist |
| `painting` | borderless, full-bleed artwork, caption | a painting |
| `celestial` | borderless, dark, star field, data grid | a celestial object |

A finish is printed on the artwork window, on the frame, or on the whole
card depending on the template (`FinishRegion`). `CardTheme` restyles frames,
paper, corner radius, typography and the card back.

## Booster flow

`PackCarouselView` presents sealed packs; the centred one opens.
`PackOpeningView(pack:design:)`: tear the top band (drag from an edge). The
pack is rendered as real pieces while tearing (`TornPackView`): the torn part
of the band rolls up into a scroll that travels with the finger (`ck_curl`,
inner foil face with the mirrored print, cylinder shading, cast shadow) and
flies off at the break, while `ck_sparks` throws a hot core, an ember trail
and flying sparks from the cutting point. One continuous deck then rises out
of the pack, settles in the centre and flips its top card; every swipe flips
the next one. The pack itself flies from the frame it was tapped in
(`arrivesFrom`, reported by `PackCarouselView`). Foil cards react to the finger, rare pulls get a burst behind them.
Packs share the card ratio, so nothing shows until the pack opens.
`PackDesign` changes the wrapper (colours, foil hue, cover, emblem). The
generic `tearable` modifier (any view, any direction) uses the `ck_tear`
shader instead.

## Build, run, test

```sh
cd Packages/CardKit && swift build && swift test
xcodebuild -project "Amazing Cards/Amazing Cards.xcodeproj" -scheme "Amazing Cards" \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

The demo accepts `-demoRoute collection|effects|animations|booster` to open a
screen directly.

## Credits

Sample images are public domain (Wikimedia Commons: Van Gogh paintings;
NASA/ESA Hubble: Orion, Pillars of Creation; NASA/JPL/SSI: Saturn; Adam Evans:
Andromeda). Shader looks are original work inspired by physical foils and by
[ShaderKit](https://github.com/jamesrochabrun/ShaderKit) (MIT),
[pokemon-cards-css](https://github.com/simeydotme/pokemon-cards-css) (GPL, not
copied) and [TearKit](https://github.com/NSStudent/TearKit).
