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

    val isTimeDriven: Boolean
        get() = when (this) {
            is Holo -> style.isTimeDriven
            is Sparkle, is Shimmer, is Starfield, is Nebula, is Burst -> true
            is Glare, is Sweep, is HoloPaper, is FoilWrap -> false
        }

    internal val program: String
        get() = when (this) {
            is Holo -> "holo"; is Glare -> "glare"; is Sparkle -> "sparkle"; is Sweep -> "sweep"; is Shimmer -> "shimmer"
            is HoloPaper -> "holoPaper"; is FoilWrap -> "foilWrap"; is Starfield -> "starfield"; is Nebula -> "nebula"; is Burst -> "burst"
        }

    /** Sets every uniform of this pass on its shader. */
    internal fun bind(shader: RuntimeShader, motion: CardMotion, width: Float, height: Float) {
        shader.setFloatUniform("size", width, height)
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
     * The passes chained as one Canvas shader reading [input] (a bitmap shader, already
     * scaled to the drawing area): pass N samples pass N−1. Null when nothing applies.
     */
    fun chain(context: Context, effects: List<CardEffect>, input: Shader, motion: CardMotion, width: Float, height: Float): Shader? {
        if (!isSupported || effects.isEmpty() || width <= 0 || height <= 0) return null
        var previous: Shader = input
        var applied = 0
        for (effect in effects) {
            val shader = shader(context, effect) ?: continue
            effect.bind(shader, motion, width, height)
            shader.setInputShader("content", previous)
            previous = shader
            applied += 1
        }
        return if (applied == 0) null else previous
    }

    /** The glare as a SCREEN-blended overlay (see glareOverlay.agsl), for a whole card. */
    fun glareOverlay(context: Context, glare: CardEffect.Glare, motion: CardMotion, width: Float, height: Float): Shader? {
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
