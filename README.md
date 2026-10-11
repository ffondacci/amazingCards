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
| `CardCore` | Pure models: `Card`, `CardContent` (creature / artist / painting / celestial), `ParallaxDesign` (layers: picture, glow backdrop, big word, title, text box, specs; neon or rim frame; specks; back), `Rarity`, `CardFinish`, `BoosterPack`, `BoosterGenerator`, `SeededRandomNumberGenerator`. No UI. |
| `CardFX` | Metal shaders + SwiftUI modifiers: `CardEffect`, `HoloStyle`, `cardMotion(...)` (apply it *outside* the effects), `CardMotionStage`, `TiltTransform`, `DeviceMotionSource`, animatable `cardSweep` / `cardDissolve` / `cardRipple`, `renderScale(_:)` for cheap backgrounds, `CardFXShaders.warmUp(first:)`. |
| `CardUI` | `CardView` (picks a template per content), `ParallaxCardView` (a layered card: layers at depths slide apart as it tilts, drag to turn, tap twice to flip, `ParallaxMode` card / stack / spread), `CardMetrics` (size-relative layout), `FinishRecipe`, `CardTheme`, `CardBackView`, `FlippableCardView`, `InteractiveCardView`, `CardFanView`, `ArtworkView` + `ArtworkLoader` actor, `cardIdleFloat`, `cardShake`, `.cardDissolve()` transition. |
| `CardStage` | Metal 3D stage (`StageView`, `StageScene`, `StageSettings`): foil pouches on a carousel in an analytic studio (puff, wrinkles, crimped seals, holo foil, clear coat, floor reflection, shadow, shine sweep), the six openings (`OpeningStyle`: tear, rip, zip, melt, roll, lid), the deal of the cards with the rare one revealed last, flakes, sparks, smoke and the aura. Pictures come in as `PackSkin` / `CardSkin`. |
| `CardPack` | `PackStageView` (the stage printed with `PackDesign`s, dealing our cards), `PackPrints` (renders pack and card pictures for the stage), `PackBackView`, `PackLayout` + `.packLayout(_:)` (every size of the pack flow as fractions: `.standard`, `.compact`, `.large`), `PackDesign` (pocket-pack layout: thick top band, double seam, full-bleed cover, thin bottom band, foil and prism strength), `BoosterPackView` (tall pouch with crimped seals, `PackShape` silhouette, flat glossy print), `PackCarouselView`, `tearable(...)` + `TearState` + `TornEdgeShape`, `TornPackView` (strip rolls up with `ck_curl`, sparks and paper flecks with `ck_sparks`, tension under the finger, bag mouth with `ck_mouth`), `CardSwipeStack`, `PackOpeningView` + `PackOpeningModel`, `PackSoundscape` + `PackSoundSet` (your own sound files for the tear), `PackWarmUpView`. |

Dependency direction: `CardCore ← CardFX ← CardUI ← CardPack`, with `CardStage` (`CardCore` only) under `CardPack`.

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

The booster experience is the 3D stage of `CardStage`, driven by
`PackStageView(designs:settings:selection:preparedCards:onPhase:onOpen:)`:
every `PackDesign` is printed (front, back and foil masks, rendered by
`PackPrints` from `BoosterPackView` and `PackBackView`) on a foil pouch
standing on a carousel in a daylight studio (a cool grey sweep with a pool of
light on the floor) or a night room (the room is drawn by the stage too, with
the light rays and halo behind the dealt cards, the dim around the rare one
and the flash of its reveal). Drag a pack to turn
it, drag beside it to browse, tap the front one: it flies in front of the
camera, waits for the swipe (or opens by itself), comes apart in the chosen
style (`StageSettings.opening`: tear the strip off, rip it in two from the
middle, pull the zip tab across a perforated line, melt it with a glowing
scorch, roll it up, or flip it open like a lid, each with its own way of
pouring the cards out), drops away while the cards rise out of its mouth,
and deals them one tap at a time, the rare one face down with a halo,
then revealed with a flash and a burst of golden flakes; a last tap fans the
five out, another puts them away. `onOpen` hands back the `CardSkin`s to deal
(our `CardView` fronts and `CardBackView` backs, rendered by
`PackPrints.cardSkins(for:)`); `preparedCards` lets the host upload the next
deal while the carousel idles, so the tap never stalls. Every dial is in
`StageSettings` (packs, spacing, depth, fov, tilt, float, reflection, shadow,
lighting, puff, wrinkles, foil, holo, gloss, shine, opening, speed, hold,
autoOpen, rareLast, guide, hints, particles, rays). The look and the
choreography follow MetalForge's Booster (metalforge.xyz/booster) frame for
frame; the implementation (Metal renderer, analytic room, procedural pouch
and wrinkle map, CPU particles) is original.

The 2D bricks of the previous flow stay available: `PackOpeningView`,
`TornPackView` (strip rolling up with `ck_curl`, sparks with `ck_sparks`, bag
mouth with `ck_mouth`), `CardSwipeStack`, the generic `tearable` modifier
(`ck_tear`), `PackLayout` for their sizes, `PackSoundscape` + `PackSoundSet`
for sound files, `PackWarmUpView`.

## Parallax cards

`ParallaxCardView(design:mode:flips:)` draws a `ParallaxDesign`: a 2:3 card
whose picture is a stack of layers, each with a depth. Tilt it (drag, or
the device tilt from `cardMotion`) and the layers slide apart by their
depth; layers that "pop" stand out of the window in 3D. Layer types: a
picture (full-bleed or free, with halo, shadow, reflection, a light that
slides across it and a breathing scale; pictures without transparency can
be cut out on black), a glowing backdrop (tone, rays, rings, floor), a big
word, a title with a badge, a text box and four specs. Two looks: a neon
frame around a window, or a rimmed poster. The card sways by itself, shows
a glare on its glass, floating specks (stardust, twinkle, glitter), and has
a back. `ParallaxMode.stack` pulls the layers apart in depth on outlined
glass plates, `.spread` lays them side by side. Choreography and looks
follow MetalForge's Parallax Cards; the SwiftUI implementation (projection
transforms, springs, Canvas specks) is original.

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
