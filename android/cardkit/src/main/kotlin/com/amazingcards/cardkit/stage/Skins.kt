// Pictures handed to the stage: packed as RGBA bytes, top row first.
package com.amazingcards.cardkit.stage

import android.graphics.Bitmap
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Pictures printed on one pack: front, back (defaults to the front) and their masks. */
class PackSkin(val id: String, val front: Bitmap, val back: Bitmap? = null, val frontMask: Bitmap? = null, val backMask: Bitmap? = null)

/** Pictures of one card dealt out of a pack; a null mask means a laminated print. */
class CardSkin(val id: String, val front: Bitmap, val back: Bitmap, val mask: Bitmap? = null)

internal fun Bitmap.toRGBA(): ByteBuffer {
    val source = if (config == Bitmap.Config.ARGB_8888) this else copy(Bitmap.Config.ARGB_8888, false)
    val buffer = ByteBuffer.allocateDirect(source.width * source.height * 4).order(ByteOrder.nativeOrder())
    source.copyPixelsToBuffer(buffer)
    buffer.rewind()
    return buffer
}

/** Several same-sized bitmaps back to back in one buffer. */
internal fun List<Bitmap>.toRGBA(width: Int, height: Int): ByteBuffer {
    val buffer = ByteBuffer.allocateDirect(size * width * height * 4).order(ByteOrder.nativeOrder())
    for (bitmap in this) {
        val scaled = if (bitmap.width == width && bitmap.height == height) bitmap else Bitmap.createScaledBitmap(bitmap, width, height, true)
        val source = if (scaled.config == Bitmap.Config.ARGB_8888) scaled else scaled.copy(Bitmap.Config.ARGB_8888, false)
        source.copyPixelsToBuffer(buffer)
    }
    buffer.rewind()
    return buffer
}
