// Every dial of the stage, a mirror of StageSettings.swift.
package com.amazingcards.cardkit.stage

enum class StageLighting { STUDIO, NIGHT }

/** How the front pack comes apart. */
enum class OpeningStyle(val label: String, val hint: String) {
    TEAR("Tear", "Swipe across the strip to tear it"),
    RIP("Rip", "Swipe to rip it apart"),
    ZIP("Zip", "Swipe to pull the tab"),
    MELT("Melt", "Swipe to melt the seal"),
    ROLL("Roll", "Swipe to roll it open"),
    LID("Lid", "Swipe to lift the lid"),
}

enum class StagePhase { IDLE, ZOOM, READY, CUT, OPEN, PRESENT, FAN, EXIT }

data class StageSettings(
    val packs: Int = 5,
    val spacing: Float = 1f,
    val depth: Float = 0.82f,
    val fov: Float = 28f,
    val tilt: Float = 1f,
    val floats: Boolean = true,
    val reflection: Float = 1f,
    val shadow: Float = 1f,
    val lighting: StageLighting = StageLighting.STUDIO,
    val background: Boolean = true,
    val puff: Float = 0.55f,
    val wrinkles: Float = 0.5f,
    val foil: Float = 1f,
    val holo: Float = 1f,
    val gloss: Float = 0.8f,
    val shine: Float = 0.55f,
    val opening: OpeningStyle = OpeningStyle.TEAR,
    val speed: Float = 1f,
    val hold: Float = 0.3f,
    val autoOpen: Float = 6f,
    val rareLast: Boolean = true,
    val guide: Boolean = true,
    val hints: Boolean = true,
    val particles: Float = 1f,
    val rays: Boolean = true,
) {
    internal fun toFloatArray(): FloatArray = floatArrayOf(
        packs.toFloat(), spacing, depth, fov, tilt, if (floats) 1f else 0f, reflection, shadow,
        if (lighting == StageLighting.NIGHT) 1f else 0f, if (background) 1f else 0f,
        puff, wrinkles, foil, holo, gloss, shine, opening.ordinal.toFloat(), speed, hold, autoOpen,
        if (rareLast) 1f else 0f, if (guide) 1f else 0f, if (hints) 1f else 0f, particles, if (rays) 1f else 0f,
    )

    companion object { val STANDARD = StageSettings() }
}
