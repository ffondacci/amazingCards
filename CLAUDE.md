# CLAUDE.md — Amazing Cards

Technical building blocks ("bricks") for a future collectible-card application: card models,
Metal holographic effects, card templates, interactive tilt, booster-pack opening. Everything
here is meant to be reused by other apps through the `CardKit` Swift package. The demo app only
showcases the bricks.

Everything committed to git is written in English (code, comments, commits, docs).
Conversations with Florent happen in French.

## Repository layout

```
Packages/CardKit/                 Swift package — THE deliverable, reusable in other apps
  Sources/CardCore/               Pure models (Sendable, Codable). No SwiftUI, no UIKit.
  Sources/CardFX/                 Metal shaders (.metal) + SwiftUI effect modifiers + motion (tilt/gyro)
  Sources/CardUI/                 Card views, templates, interaction containers, animations
  Sources/CardPack/               Booster pack, tear gesture, pack-opening flow, swipe stack
  Tests/                          Swift Testing (`import Testing`), no XCTest
Amazing Cards/                    Demo app (Xcode project, folder-synchronized target)
  Amazing Cards/App/              App entry, root navigation, launch-argument routing
  Amazing Cards/Demo/             Catalog screens (collection, effects, animations, booster)
  Amazing Cards/Samples/          Sample cards (Van Gogh, paintings, celestial objects)
  Amazing Cards/Assets.xcassets   Sample images (public domain, Wikimedia)
android/                          Android port of the booster stage (Vulkan) + Compose demo
  cardkit/src/main/cpp/           C++ scene + Vulkan renderer + JNI, GLSL shaders (glslc → assets)
  cardkit/src/main/kotlin/        Kotlin models, Canvas prints, Stage / StageView / PackStageView
  demo/                           Demo app (Collection, Booster)
ressources/                       Raw source material (not shipped)
```

Dependency direction is strict: `CardCore ← CardFX ← CardUI ← CardPack ← App`. Never import a
higher layer from a lower one. The app never contains reusable logic: if something is useful
elsewhere, it goes into the package.

## Non-negotiable guidelines

### Swift only, modern Swift
- Swift 6 language mode, strict concurrency, `swift-tools-version: 6.2`. No Objective-C, no C++.
- Value types first. `struct`/`enum` for models and views. A `class` only for shared mutable state,
  then it is `@MainActor @Observable final class` or an `actor`.
- Protocol-oriented where it helps composition, never for a single implementation.
- Public API of the package is documented with `///` doc comments. Types are small and focused.
- No singletons for state. Dependencies are passed in or injected through the SwiftUI environment.

### Concurrency: async/await, everything cancellable
- Only `async`/`await`, `Task`, `TaskGroup`, `AsyncStream`, actors. No GCD, no `DispatchQueue`,
  no completion handlers, no Combine, no `Timer` (use `TimelineView` or `AsyncTimerSequence`
  patterns with `Task.sleep`).
- Every unit of asynchronous work must be cancellable. Prefer structured concurrency:
  `.task {}` / `.task(id:)` on views (auto-cancelled on disappear), `withTaskGroup`,
  `withTaskCancellationHandler` for callback-based APIs (CoreMotion, ImageIO).
- An unstructured `Task { }` must be stored and cancelled explicitly (`task?.cancel()` in
  `stop()` / `onDisappear`). Long loops check `Task.isCancelled` or call `try Task.checkCancellation()`.
- `nonisolated(unsafe)`, `@unchecked Sendable`, `@preconcurrency import` and `Task.detached` are
  forbidden unless a comment explains why no alternative exists. Reviewer rejects by default.

### Zero data races, zero leaks
- Everything crossing an isolation boundary is `Sendable`. Models in `CardCore` are `Sendable`
  and `Codable`. Non-Sendable framework objects (`CMDeviceMotion`, `CGImage` sources, …) are
  unwrapped into plain values before leaving their isolation domain.
- UI state lives on the main actor (`@MainActor`). Heavy work (image decoding, pack generation,
  parsing) lives in an `actor` or a `nonisolated` async function and returns values.
- No retain cycles: closures stored by a class capture `[weak self]`; views never hold strong
  references to observable models they did not create (use `@Environment` / `@Bindable`).
- Timeline-driven animations (`TimelineView(.animation)`) are paused when the view is idle,
  off-screen or when Reduce Motion is on. Nothing animates forever "just in case".

### Performance: 60/120 fps, no hitches
- Shader effects: prefer `colorEffect` (per-pixel, no sampling) over `layerEffect` (needs a
  sampled layer); `distortionEffect` only for geometry. One shader pass per visual effect; compose
  cheap passes rather than one monolithic uber-shader with branches per pixel.
- Keep every per-frame closure (`visualEffect`, `TimelineView` body) allocation-free and trivial.
  No `GeometryReader` in hot paths: use `visualEffect { content, proxy in … }` to read sizes.
- Images are decoded once, downsampled to the display size with ImageIO, cached in an actor.
  Never decode on the main actor.
- Avoid `AnyView`, avoid deep conditional view hierarchies that change identity. Use `.id`
  intentionally. Prefer `.animation(_:value:)` to implicit animations.
- Measure before optimizing: Instruments (SwiftUI, Core Animation, Metal System Trace) on a
  real device. The demo must stay smooth on an iPhone with ProMotion and on an iPad.

### Layout and UI: fits every aspect ratio
- A card is always drawn relative to its own size: `CardMetrics(size:)` derives every font size,
  radius, inset and stroke from the card width. Cards never use hard-coded point values.
- The card aspect ratio is fixed (63 × 88 mm, ratio 0.716). The container, not the card,
  decides the size: `.aspectRatio(CardMetrics.aspectRatio, contentMode: .fit)` inside the
  available space. Screens are tested on iPhone (compact), iPhone landscape, iPad (regular),
  split-view multitasking and the tall/narrow "iPhone duo" ratio.
- Use `ViewThatFits`, adaptive grids (`LazyVGrid(columns: [.adaptive(minimum:)])`),
  `NavigationSplitView`/`.sidebarAdaptable` tabs, safe-area insets, dynamic type. No `UIScreen`.
- Respect `accessibilityReduceMotion`, `accessibilityReduceTransparency`, dark mode.

## Shader conventions (`CardFX/Shaders/*.metal`)
- Every stitchable function is prefixed `ck_` and lives in one Metal library
  (`ShaderLibrary.bundle(.module)`), accessed only through `CardFXShaders`.
- Signatures follow SwiftUI: `colorEffect` → `(float2 position, half4 color, …)`,
  `layerEffect` → `(float2 position, SwiftUI::Layer layer, …)`, `distortionEffect` →
  `float2 (float2 position, …)`.
- First extra arguments are always `float2 size`, then `float2 tilt` (−1…1), `float2 pointer`
  (0…1, negative when absent), `float time`, then effect parameters. Swift and Metal argument
  order must match exactly, there is no runtime check.
- Procedural only: no texture assets. Helpers (`hash`, `noise`, `fbm`, `spectrum`, blend modes)
  are `static inline` per file (no shared headers in SwiftPM Metal targets).
- Original implementations. References (ShaderKit — MIT, pokemon-cards-css — GPL, TearKit —
  no license) are inspiration for the look, never copied.

## Build, run, test

```sh
# Type-check the package quickly (macOS host, shaders are not compiled by SwiftPM CLI)
cd Packages/CardKit && swift build && swift test

# Full build with Metal compilation, iPhone simulator
xcodebuild -project "Amazing Cards/Amazing Cards.xcodeproj" -scheme "Amazing Cards" \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# Launch straight into a demo screen (used for screenshots and QA)
xcrun simctl launch booted <bundle-id> -demoRoute effects   # collection | effects | animations | booster
```

A change is done only when: the package builds with zero warnings, tests pass, the demo app
builds, and the affected screen has been looked at on both an iPhone and an iPad simulator.

```sh
# Android (same stage in Vulkan): build, install on the emulator, screenshot
cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :demo:assembleDebug
adb install -r demo/build/outputs/apk/debug/demo-debug.apk
adb shell am start -n com.amazingcards.demo/.MainActivity --es demoRoute booster --es openAfter 2000
adb exec-out screencap -p > shot.png
```

The Android stage must stay a faithful port: `android/cardkit/src/main/cpp/stage_*.cpp` mirror the
Swift files of `CardStage` one for one, and `shaders/*.glsl` mirror the Metal shaders (same uniform
layouts, same dials, same constants). A change to the choreography or the shading lands on both.

## Conventions
- Commit messages: English, imperative, explain the why. Jira keys only in commit messages.
- One feature per file group, `// MARK:` sections, no file longer than ~400 lines.
- Public API changes in the package are reflected in `README.md` (catalog of bricks).
