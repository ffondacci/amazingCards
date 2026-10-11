// The booster stage: a native Vulkan scene with its renderer, driven from
// the UI thread. Observable state (phase, hint, front index) is published
// on the main thread for Compose.
package com.amazingcards.cardkit.stage

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

class Stage(context: Context, initial: StageSettings = StageSettings.STANDARD) {
    private val main = Handler(Looper.getMainLooper())
    private var handle: Long
    private val callbacks = object : StageCallbacks {
        override fun onPhase(phase: Int) { main.post { this@Stage.phase = StagePhase.entries[phase.coerceIn(0, StagePhase.entries.size - 1)] } }
        override fun onHint(text: String) { main.post { hint = text.ifEmpty { null } } }
        override fun onOpened(index: Int) { main.post { onOpened?.invoke(index) } }
    }

    var phase by mutableStateOf(StagePhase.IDLE)
        private set
    var hint by mutableStateOf<String?>(null)
        private set
    var settings: StageSettings = initial
        set(value) { field = value; StageNative.setSettings(handle, value.toFloatArray()) }
    /** Called with the index of the pack that just opened, so the host prepares the next deal. */
    var onOpened: ((Int) -> Unit)? = null
    private val density = context.resources.displayMetrics.density

    init {
        handle = StageNative.create(context.assets, callbacks, density)
        StageNative.setSettings(handle, initial.toFloatArray())
    }

    fun setSurface(surface: Surface?) = StageNative.setSurface(handle, surface)
    fun resize(width: Int, height: Int) = StageNative.resize(handle, width, height, density)

    fun setSkin(index: Int, skin: PackSkin?) {
        if (skin == null) { StageNative.setSkin(handle, index, "", 0, 0, null, null, 0, 0, null, null); return }
        val w = skin.front.width; val h = skin.front.height
        val mask = skin.frontMask
        StageNative.setSkin(
            handle, index, skin.id, w, h, skin.front.toRGBA(), skin.back?.toRGBA(),
            mask?.width ?: 0, mask?.height ?: 0, mask?.toRGBA(), skin.backMask?.toRGBA(),
        )
    }

    /** The cards of the next deal, uploaded ahead of the tap. */
    fun prepareCards(cards: List<CardSkin>) {
        if (cards.isEmpty()) { StageNative.prepareCards(handle, emptyArray(), 0, 0, null, null, 0, 0, null); return }
        val w = cards[0].front.width; val h = cards[0].front.height
        val fronts = cards.map { it.front }.toRGBA(w, h)
        val backs = cards.map { it.back }.toRGBA(w, h)
        val hasMask = cards.any { it.mask != null }
        val mw = if (hasMask) 4 else 0; val mh = if (hasMask) 4 else 0
        val masks = if (hasMask) cards.map { it.mask ?: plainMask() }.toRGBA(mw, mh) else null
        StageNative.prepareCards(handle, cards.map { it.id }.toTypedArray(), w, h, fronts, backs, mw, mh, masks)
    }

    private fun plainMask(): android.graphics.Bitmap {
        val b = android.graphics.Bitmap.createBitmap(4, 4, android.graphics.Bitmap.Config.ARGB_8888)
        b.eraseColor(android.graphics.Color.rgb(0, 0, 90))
        return b
    }

    fun pointer(active: Boolean, x: Float, y: Float) = StageNative.pointer(handle, active, x, y)
    fun tilt(x: Float, y: Float) = StageNative.tilt(handle, x, y)
    fun dragBegan(x: Float, y: Float, time: Double) = StageNative.dragBegan(handle, x, y, time)
    fun dragChanged(x: Float, y: Float, time: Double) = StageNative.dragChanged(handle, x, y, time)
    fun dragEnded(x: Float, y: Float, time: Double) = StageNative.dragEnded(handle, x, y, time)
    /** Opens the front pack with the prepared cards. */
    fun open() = StageNative.open(handle)
    fun exit() = StageNative.exit(handle)
    fun bringToFront(index: Int) = StageNative.bringToFront(handle, index)

    fun destroy() {
        if (handle != 0L) { StageNative.destroy(handle); handle = 0L }
    }
}
