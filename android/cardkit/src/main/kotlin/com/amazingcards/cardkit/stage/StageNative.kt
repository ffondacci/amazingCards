// The JNI surface of the native stage (stage_jni.cpp).
package com.amazingcards.cardkit.stage

import android.content.res.AssetManager
import android.view.Surface
import java.nio.ByteBuffer

internal interface StageCallbacks {
    fun onPhase(phase: Int)
    fun onHint(text: String)
    fun onOpened(index: Int)
}

internal object StageNative {
    init { System.loadLibrary("cardstage") }

    external fun create(assets: AssetManager, callbacks: StageCallbacks, density: Float): Long
    external fun destroy(handle: Long)
    external fun setSurface(handle: Long, surface: Surface?)
    external fun resize(handle: Long, width: Int, height: Int, density: Float)
    external fun setSettings(handle: Long, values: FloatArray)
    external fun setSkin(handle: Long, index: Int, id: String, width: Int, height: Int, front: ByteBuffer?, back: ByteBuffer?, maskWidth: Int, maskHeight: Int, frontMask: ByteBuffer?, backMask: ByteBuffer?)
    external fun prepareCards(handle: Long, ids: Array<String>, width: Int, height: Int, fronts: ByteBuffer?, backs: ByteBuffer?, maskWidth: Int, maskHeight: Int, masks: ByteBuffer?)
    external fun pointer(handle: Long, active: Boolean, x: Float, y: Float)
    external fun tilt(handle: Long, x: Float, y: Float)
    external fun dragBegan(handle: Long, x: Float, y: Float, time: Double)
    external fun dragChanged(handle: Long, x: Float, y: Float, time: Double)
    external fun dragEnded(handle: Long, x: Float, y: Float, time: Double)
    external fun open(handle: Long)
    external fun exit(handle: Long)
    external fun bringToFront(handle: Long, index: Int)
}
