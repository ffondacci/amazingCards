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
| `CardPack` | `PackLayout` + `.packLayout(_:)` (every size of the pack flow as fractions: `.standard`, `.compact`, `.large`), `PackDesign` (pocket-pack layout: thick top band, double seam, full-bleed cover, thin bottom band, foil and prism strength), `BoosterPackView` (tall pouch with crimped seals, `PackShape` silhouette, flat glossy print), `PackCarouselView`, `tearable(...)` + `TearState` + `TornEdgeShape`, `TornPackView` (strip rolls up with `ck_curl`, sparks and paper flecks with `ck_sparks`, tension under the finger, bag mouth with `ck_mouth`), `CardSwipeStack`, `PackOpeningView` + `PackOpeningModel`, `PackSoundscape` + `PackSoundSet` (your own sound files for the tear), `PackWarmUpView`. |

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

Sizes come from one `PackLayout` (fractions of the available space plus an
optional cap), set once for the app with `.packLayout(.large)`. The pack is
sized first (as wide as the cards may be, no taller than its height
fraction) and the cards derive from it, a hair narrower, so the deck stays
hidden behind the sealed pack.
`PackCarouselView` presents sealed packs; the centred one opens.
`PackOpeningView(pack:design:)`: tear the top band (drag from an edge). The
pack is rendered as real pieces while tearing (`TornPackView`): the torn part
of the band rolls up into a scroll that travels with the finger (`ck_curl`,
inner foil face with the mirrored print, cylinder shading, cast shadow) and
flies off at the break, while `ck_sparks` throws a hot core, an ember trail,
flying sparks and flecks from the cutting point, and the torn body opens
like a bag mouth while the cards slide out (`ck_mouth`). The wrapper itself
is a flat glossy print with a foil sheen and a faint prism; the crumpled
paper (`ck_paper`, facets, sheen and crease marks, adapted from Paper
Design's paper-texture shader, Apache-2.0) and the paper tension under a
finger (`ck_paperTension`) stay available as effects for any view.
`PackSoundscape` plays three optional sound files (`PackSoundSet`: crinkle
on grab, a tearing loop whose volume follows the finger, a whoosh at the
break); none are bundled, pass your own to `PackOpeningView(sounds:)`. One continuous deck then rises out
of the pack, settles in the centre and flips its top card; every swipe flips
the next one. The pack itself flies from the frame it was tapped in
(`arrivesFrom`, reported by `PackCarouselView`). Foil cards react to the finger, rare pulls get a burst behind them.
Packs are tall pouches (`PackDesign.aspectRatio`, 0.58) in the pocket-pack
proportions: a top band of about a sixth of the height, a bottom band of
a sixteenth, crimped seals at both ends and sides that bow out a little
(`PackShape`). `PackDesign` changes the wrapper (colours, foil hue, cover,
emblem, band fractions). The
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
