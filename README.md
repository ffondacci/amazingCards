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
| `CardFX` | Metal shaders + SwiftUI modifiers: `CardEffect`, `HoloStyle`, `cardMotion(...)` (apply it *outside* the effects), `CardMotionStage`, `TiltTransform`, `DeviceMotionSource`, animatable `cardSweep` / `cardDissolve` / `cardRipple`, `renderScale(_:)` for cheap backgrounds, `CardFXShaders.warmUp(first:)`. |
| `CardUI` | `CardView` (picks a template per content), `CardMetrics` (size-relative layout), `FinishRecipe`, `CardTheme`, `CardBackView`, `FlippableCardView`, `InteractiveCardView`, `CardFanView`, `ArtworkView` + `ArtworkLoader` actor, `cardIdleFloat`, `cardShake`, `.cardDissolve()` transition. |
| `CardPack` | `PackDesign` (pocket-pack layout: top band, seam, full-bleed cover, bottom band), `BoosterPackView` (lit paper wrapper: folds, wrinkles, crimps, bulge), `PackCarouselView`, `tearable(...)` + `TearState` + `TornEdgeShape`, `TornPackView` (strip rolls up with `ck_curl`, sparks and paper flecks with `ck_sparks`, tension under the finger, bag mouth with `ck_mouth`), `CardSwipeStack`, `PackOpeningView` + `PackOpeningModel`, `PackSoundscape` (procedural crinkle, tear, whoosh), `PackWarmUpView`. |

Dependency direction: `CardCore ← CardFX ← CardUI ← CardPack`.

## Effects (`CardEffect`)

Foil styles rendered by one shader (`ck_holo`, `HoloStyle`): regular holo,
cosmos, reverse holo, galaxy, rainbow, gold, amazing, radiant, prism, pearl,
brushed metal, full art, interference.

Overlays and generators: glare, sparkle, light sweep, shimmer, holo paper,
foil wrapper, star field, nebula (4 palettes), burst, sparks (with paper
flecks), paper (lit folds, wrinkles, crimps, bulge), paper tension (dent under
the finger, ripples ahead of a cut), chromatic split, dissolve. Geometry: tear
(`ck_tear`), strip curl (`ck_curl`), bag mouth (`ck_mouth`), ripple (`ck_ripple`).

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
flies off at the break, while `ck_sparks` throws a hot core, an ember trail,
flying sparks and paper flecks from the cutting point. The wrapper is
crumpled paper (`ck_paper`, a layer effect): a field of flat facets, each with
its own slope, blended across rounded shoulders at the creases; large crumples
come from a handful of seed points and wrinkles from two octaves of a sparse
cellular grid. A grazing light that follows the tilt darkens every facet
turning away from it, each facet returns its own sheen, the print bends gently
with the large facets, sharp creases facing the light leave a whitened mark,
and crimp bumps plus the bulge of the cards (deflating once they leave) sit on
top. The paper tenses under the finger and ripples ahead of the cut
(`ck_paperTension`), and the torn body opens like a bag mouth while the cards
slide out (`ck_mouth`). The facet model is adapted from Paper Design's
paper-texture shader (Apache-2.0).
`PackSoundscape` synthesizes the crinkle, the tearing (pitched by finger
speed) and the whoosh in the audio render callback, with no audio files. One continuous deck then rises out
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
screen directly, and `-showFPS YES` to overlay a display-link frame counter
(current rate and the worst half-second of the last three seconds).

## Performance notes

- Motion providers go outside the effects: `view.cardEffect(…).cardMotion(…)`.
  An effect applied outside its provider reads a frozen clock.
- Backgrounds (star field, nebula) render at half resolution with
  `renderScale(0.5)` and tick at 30 fps; the pack is rasterized once with
  `drawingGroup()` because every drag event re-masks it.
- Artwork decodes off the main actor through `ArtworkLoader`, downsampled,
  for catalog assets as well as URLs; call `prewarm(assets:)` at launch.
- `CardFXShaders.warmUp(first:)` compiles the effects of the first screen in
  parallel, then the rest one at a time at utility priority; show
  `PackWarmUpView` once at launch so the first opening is smooth.

## Credits

Sample images are public domain (Wikimedia Commons: Van Gogh paintings;
NASA/ESA Hubble: Orion, Pillars of Creation; NASA/JPL/SSI: Saturn; Adam Evans:
Andromeda). Shader looks are original work inspired by physical foils and by
[ShaderKit](https://github.com/jamesrochabrun/ShaderKit) (MIT),
[pokemon-cards-css](https://github.com/simeydotme/pokemon-cards-css) (GPL, not
copied) and [TearKit](https://github.com/NSStudent/TearKit). The crumpled-paper
facet model in `ck_paper` is adapted from
[Paper Design shaders](https://github.com/paper-design/shaders) (Apache-2.0).
