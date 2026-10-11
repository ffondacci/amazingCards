// One shader pass over a card, a mirror of CardEffect.swift. The AGSL
// programs live in assets/fx; uniforms follow the Metal argument order:
// size, tilt, pointer, time, intensity, then the effect's own parameters.
package com.amazingcards.cardkit.fx

import android.content.Context
import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.graphics.Shader
import com.amazingcards.cardkit.core.CardColor

enum class HoloStyle(val displayName: String, val isTimeDriven: Boolean) {
    REGULAR("Regular holo", false), COSMOS("Cosmos", true), REVERSE_HOLO("Reverse holo", false), GALAXY("Galaxy", true),
    RAINBOW("Rainbow", true), GOLD("Gold", true), AMAZING("Amazing", true), RADIANT("Radiant", true), PRISM("Prism", false),
    PEARL("Pearl", false), BRUSHED_METAL("Brushed metal", false), FULL_ART("Full art", false), INTERFERENCE("Interference", false),
}

enum class NebulaPalette { VIOLET, TEAL, EMBER, EMERALD }

sealed class CardEffect {
    data class Holo(val style: HoloStyle, val intensity: Float = 1f) : CardEffect()
    data class Glare(val intensity: Float = 0.55f, val radius: Float = 0.9f) : CardEffect()
    data class Sparkle(val intensity: Float = 0.8f, val density: Float = 32f) : CardEffect()
    data class Sweep(val progress: Float, val intensity: Float = 0.7f, val width: Float = 0.16f, val angle: Float = 35f) : CardEffect()
    data class Shimmer(val intensity: Float = 0.6f, val angle: Float = 20f) : CardEffect()
    data class HoloPaper(val hue: Float = 0.55f, val intensity: Float = 1f) : CardEffect()
    data class FoilWrap(val hue: Float = 0.62f, val intensity: Float = 1f) : CardEffect()
    data class Starfield(val density: Float = 40f, val intensity: Float = 1f) : CardEffect()
    data class Nebula(val palette: NebulaPalette = NebulaPalette.VIOLET, val intensity: Float = 1f) : CardEffect()
    data class Burst(val tint: CardColor = CardColor.GOLD, val intensity: Float = 1f) : CardEffect()
    /** RGB split along the tilt, `amount` in dp. */
    data class Chromatic(val amount: Float = 6f) : CardEffect()
    /** Noise dissolve, `progress` 0 = intact, 1 = gone. */
    data class Dissolve(val progress: Float, val edgeWidth: Float = 0.08f, val edgeColor: CardColor = CardColor.GOLD, val scale: Float = 6f) : CardEffect()
    /** Sparks at a cutting point (dp), thrown opposite to `direction`. */
    data class Sparks(val originX: Float, val originY: Float, val directionX: Float, val directionY: Float, val tint: CardColor = CardColor.GOLD, val intensity: Float = 1f, val life: Float = 0.45f) : CardEffect()
    /** Lit paper wrapper: folds, wrinkles, crimp bumps (`crimp` dp tall) and the bulge of the cards inside. */
    data class Paper(val bulge: Float = 1f, val crimp: Float = 0f, val intensity: Float = 1f) : CardEffect()
    /** Paper tension under a finger at (pointX, pointY) dp, ripples ahead of a cut at x = `front` running towards `direction` (±1). */
    data class PaperTension(val pointX: Float, val pointY: Float, val front: Float, val direction: Float, val strength: Float = 1f) : CardEffect()

    val isTimeDriven: Boolean
        get() = when (this) {
            is Holo -> style.isTimeDriven
            is Sparkle, is Shimmer, is Starfield, is Nebula, is Burst, is Sparks, is PaperTension -> true
            is Glare, is Sweep, is HoloPaper, is FoilWrap, is Chromatic, is Dissolve, is Paper -> false
        }

    /** True for generators that replace their source (draw them over an opaque shape). */
    val isGenerator: Boolean
        get() = when (this) { is HoloPaper, is Starfield, is Nebula, is Burst, is Sparks, is PaperTension -> true; else -> false }

    val isHolo: Boolean get() = this is Holo

    /** Sweep and dissolve are driven by a progress animation, not a slider. */
    val isAnimatable: Boolean get() = this is Sweep || this is Dissolve

    val displayName: String
        get() = when (this) {
            is Holo -> style.displayName
            is Glare -> "Glare"; is Sparkle -> "Sparkle"; is Sweep -> "Light sweep"; is Shimmer -> "Shimmer"
            is HoloPaper -> "Holo paper"; is FoilWrap -> "Foil wrapper"; is Starfield -> "Star field"
            is Nebula -> "Nebula · " + when (palette) { NebulaPalette.VIOLET -> "Violet"; NebulaPalette.TEAL -> "Teal & gold"; NebulaPalette.EMBER -> "Ember"; NebulaPalette.EMERALD -> "Emerald" }
            is Burst -> "Burst"; is Chromatic -> "Chromatic split"; is Dissolve -> "Dissolve"; is Sparks -> "Sparks"
            is Paper -> "Paper"; is PaperTension -> "Paper tension"
        }

    val summary: String
        get() = when (this) {
            is Holo -> when (style) {
                HoloStyle.REGULAR -> "Rainbow bands, scan lines and moving bars."
                HoloStyle.COSMOS -> "Three parallax star layers over a soft nebula."
                HoloStyle.REVERSE_HOLO -> "Textured silver foil meant for the frame."
                HoloStyle.GALAXY -> "Slowly drifting coloured gas clouds and stars."
                HoloStyle.RAINBOW -> "Crossing rainbow gradients with glitter."
                HoloStyle.GOLD -> "Geometric gold foil and sparkles."
                HoloStyle.AMAZING -> "Saturated paint splashes with glitter."
                HoloStyle.RADIANT -> "Etched diagonal lattice with sparkles."
                HoloStyle.PRISM -> "Diffraction rings around the finger, CD like."
                HoloStyle.PEARL -> "Thin-film iridescence driven by luminance."
                HoloStyle.BRUSHED_METAL -> "Anisotropic streaks and a specular band."
                HoloStyle.FULL_ART -> "Vertical sun-pillar rainbow with etching."
                HoloStyle.INTERFERENCE -> "Wavy interference field with ridges."
            }
            is Glare -> "Specular highlight following the finger or the tilt."
            is Sparkle -> "Twinkling glitter, brighter on light pixels."
            is Sweep -> "A light band crossing the card, animatable."
            is Shimmer -> "Placeholder shimmer while artwork loads."
            is HoloPaper -> "Printed pastel background of framed cards."
            is FoilWrap -> "Metallic crinkled wrapper of a booster pack."
            is Starfield -> "Procedural stars with parallax on tilt."
            is Nebula -> "Drifting gas clouds, four palettes."
            is Burst -> "Ray burst behind a revealed rare card."
            is Chromatic -> "RGB split along the tilt direction."
            is Dissolve -> "Noise dissolve with a glowing edge, animatable."
            is Sparks -> "Hot core, ember trail, flying sparks and paper flecks at a cut."
            is Paper -> "Folds, wrinkles and crimps lit by the tilt, with the bulge of the cards inside."
            is PaperTension -> "Dent and wrinkles under the finger, ripples ahead of the cut."
        }

    /** Same effect with its main amount multiplied. */
    fun scaled(factor: Float): CardEffect = when (this) {
        is Holo -> copy(intensity = intensity * factor)
        is Glare -> copy(intensity = intensity * factor)
        is Sparkle -> copy(intensity = intensity * factor)
        is Sweep -> this
        is Shimmer -> copy(intensity = intensity * factor)
        is HoloPaper -> copy(intensity = intensity * factor)
        is FoilWrap -> copy(intensity = intensity * factor)
        is Starfield -> copy(intensity = intensity * factor)
        is Nebula -> copy(intensity = intensity * factor)
        is Burst -> copy(intensity = intensity * factor)
        is Chromatic -> copy(amount = amount * factor * 2)
        is Dissolve -> this
        is Sparks -> copy(intensity = intensity * factor)
        is Paper -> copy(intensity = intensity * factor)
        is PaperTension -> copy(strength = strength * factor)
    }

    internal val program: String
        get() = when (this) {
            is Holo -> "holo"; is Glare -> "glare"; is Sparkle -> "sparkle"; is Sweep -> "sweep"; is Shimmer -> "shimmer"
            is HoloPaper -> "holoPaper"; is FoilWrap -> "foilWrap"; is Starfield -> "starfield"; is Nebula -> "nebula"; is Burst -> "burst"
            is Chromatic -> "chromatic"; is Dissolve -> "dissolve"; is Sparks -> "sparks"; is Paper -> "paper"; is PaperTension -> "paperTension"
        }

    companion object {
        /** One representative of each effect, for catalogs. Positions are in dp, like the SwiftUI points. */
        val showcase: List<CardEffect> =
            HoloStyle.entries.map { Holo(it) } + listOf(
                Glare(), Sparkle(), Sweep(progress = 0.5f), Shimmer(), HoloPaper(), FoilWrap(),
                Starfield(), Nebula(NebulaPalette.VIOLET), Nebula(NebulaPalette.TEAL), Nebula(NebulaPalette.EMBER),
                Nebula(NebulaPalette.EMERALD), Burst(), Chromatic(), Dissolve(progress = 0.3f),
                Sparks(150f, 60f, 1f, 0f),
                Paper(bulge = 1f, crimp = 14f),
                PaperTension(150f, 60f, 150f, 1f),
            )
    }

    /** Sets every uniform of this pass on its shader. */
    internal fun bind(shader: RuntimeShader, motion: CardMotion, width: Float, height: Float) {
        shader.setFloatUniform("size", width, height)
        // Passes with their own argument list (see CardEffect.swift).
        when (this) {
            is Chromatic -> { shader.setFloatUniform("tilt", motion.tiltX, motion.tiltY); shader.setFloatUniform("amount", amount); return }
            is Dissolve -> { shader.setFloatUniform("progress", progress); shader.setFloatUniform("edgeWidth", edgeWidth); shader.setFloatUniform("edgeColor", edgeColor.red.toFloat(), edgeColor.green.toFloat(), edgeColor.blue.toFloat()); shader.setFloatUniform("scale", scale); return }
            is Sparks -> { shader.setFloatUniform("origin", originX, originY); shader.setFloatUniform("direction", directionX, directionY); shader.setFloatUniform("time", motion.time); shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("tint", tint.red.toFloat(), tint.green.toFloat(), tint.blue.toFloat()); shader.setFloatUniform("life", life); return }
            is PaperTension -> { shader.setFloatUniform("point", pointX, pointY); shader.setFloatUniform("front", front); shader.setFloatUniform("direction", direction); shader.setFloatUniform("strength", strength); shader.setFloatUniform("time", motion.time); return }
            else -> {}
        }
        shader.setFloatUniform("tilt", motion.tiltX, motion.tiltY)
        val p = motion.pointer
        shader.setFloatUniform("pointer", p?.first ?: -1f, p?.second ?: -1f)
        shader.setFloatUniform("time", motion.time)
        when (this) {
            is Holo -> { shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("style", style.ordinal.toFloat()) }
            is Glare -> { shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("radius", radius) }
            is Sparkle -> { shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("density", density) }
            is Sweep -> { shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("progress", progress); shader.setFloatUniform("width", width); shader.setFloatUniform("angle", angle) }
            is Shimmer -> { shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("angle", angle) }
            is HoloPaper -> { shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("hue", hue) }
            is FoilWrap -> { shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("hue", hue) }
            is Starfield -> { shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("density", density) }
            is Nebula -> { shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("palette", palette.ordinal.toFloat()) }
            is Burst -> { shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("tint", tint.red.toFloat(), tint.green.toFloat(), tint.blue.toFloat()) }
            is Paper -> { shader.setFloatUniform("intensity", intensity); shader.setFloatUniform("bulge", bulge); shader.setFloatUniform("crimp", crimp) }
            is Chromatic, is Dissolve, is Sparks, is PaperTension -> {}
        }
    }
}

/** Where the card is tilted (−1…1), where the finger is (0…1, null = none), the clock. */
data class CardMotion(val tiltX: Float = 0f, val tiltY: Float = 0f, val pointer: Pair<Float, Float>? = null, val time: Float = 0f, val isInteracting: Boolean = false) {
    companion object { val STILL = CardMotion() }
}

/** Compiles the AGSL programs once and hands out shaders and render effects. */
object CardFXShaders {
    private var common: String? = null
    private val sources = HashMap<String, String>()
    private val shaders = HashMap<String, RuntimeShader>()

    val isSupported: Boolean get() = android.os.Build.VERSION.SDK_INT >= 33

    @Synchronized
    private fun source(context: Context, name: String): String {
        val head = common ?: context.assets.open("fx/common.agsl").bufferedReader().readText().also { common = it }
        return sources.getOrPut(name) { head + "\n" + context.assets.open("fx/$name.agsl").bufferedReader().readText() }
    }

    /** One shader per program, reused: uniforms are rebound before every use. */
    private val broken = HashSet<String>()

    /** Null when the program does not compile on this device (logged once, the pass is skipped). */
    @Synchronized
    fun shader(context: Context, effect: CardEffect): RuntimeShader? {
        val name = effect.program
        if (name in broken) return null
        shaders[name]?.let { return it }
        return try {
            RuntimeShader(source(context, name)).also { shaders[name] = it }
        } catch (e: IllegalArgumentException) {
            android.util.Log.e("CardFX", "AGSL $name failed to compile: ${e.message}")
            broken.add(name)
            null
        }
    }

    /** The passes chained in order (first applied first) as one render effect. */
    fun renderEffect(context: Context, effects: List<CardEffect>, motion: CardMotion, width: Float, height: Float): RenderEffect? {
        if (!isSupported || effects.isEmpty() || width <= 0 || height <= 0) return null
        var chain: RenderEffect? = null
        for (effect in effects) {
            val shader = shader(context, effect) ?: continue
            effect.bind(shader, motion, width, height)
            val pass = RenderEffect.createRuntimeShaderEffect(shader, "content")
            chain = if (chain == null) pass else RenderEffect.createChainEffect(pass, chain)
        }
        return chain
    }

    /**
     * The passes chained as one Canvas shader reading [input]: pass N samples
     * pass N−1. The passes run in density-independent pixels, like SwiftUI
     * points, so [input] must map dp to its picture and [width] / [height]
     * are in dp. Null when nothing applies.
     */
    fun chain(context: Context, effects: List<CardEffect>, input: Shader, motion: CardMotion, width: Float, height: Float, density: Float): Shader? {
        if (!isSupported || effects.isEmpty() || width <= 0 || height <= 0) return null
        val scale = android.graphics.Matrix().apply { setScale(density, density) }
        var previous: Shader = input
        var applied = 0
        for (effect in effects) {
            val shader = shader(context, effect) ?: continue
            // Everything about a pass is final before the next one snapshots it as its child.
            effect.bind(shader, motion, width, height)
            shader.setLocalMatrix(scale)
            shader.setInputShader("content", previous)
            previous = shader
            applied += 1
        }
        return if (applied == 0) null else previous
    }

    /** The glare as a SCREEN-blended overlay (see glareOverlay.agsl), for a whole card of `width × height` dp. */
    fun glareOverlay(context: Context, glare: CardEffect.Glare, motion: CardMotion, width: Float, height: Float, density: Float): Shader? {
        if (!isSupported) return null
        val shader = overlay ?: try { RuntimeShader(source(context, "glareOverlay")).also { overlay = it } } catch (e: IllegalArgumentException) {
            android.util.Log.e("CardFX", "AGSL glareOverlay failed to compile: ${e.message}"); return null
        }
        shader.setFloatUniform("size", width, height)
        shader.setFloatUniform("tilt", motion.tiltX, motion.tiltY)
        shader.setFloatUniform("pointer", motion.pointer?.first ?: -1f, motion.pointer?.second ?: -1f)
        shader.setFloatUniform("time", motion.time)
        shader.setFloatUniform("intensity", glare.intensity)
        shader.setFloatUniform("radius", glare.radius)
        shader.setLocalMatrix(android.graphics.Matrix().apply { setScale(density, density) })
        return shader
    }
    private var overlay: RuntimeShader? = null

    /** A generator (holo paper, star field, nebula) as a Canvas shader for a `width × height` area at the origin. */
    fun generator(context: Context, effect: CardEffect, width: Float, height: Float, motion: CardMotion = CardMotion.STILL): Shader? {
        if (!isSupported) return null
        val shader = shader(context, effect) ?: return null
        effect.bind(shader, motion, width, height)
        // The generators keep the alpha of their input: an opaque white input.
        shader.setInputShader("content", android.graphics.LinearGradient(0f, 0f, 1f, 0f, intArrayOf(android.graphics.Color.WHITE, android.graphics.Color.WHITE), null, Shader.TileMode.CLAMP))
        return shader
    }
}
