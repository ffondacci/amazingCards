// Renders a drawing on the GPU into a software bitmap: runtime shaders
// (the AGSL generators) only work on hardware canvases, and the card
// painter draws into plain bitmaps.
package com.amazingcards.cardkit.paint

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorSpace
import android.graphics.HardwareRenderer
import android.graphics.PixelFormat
import android.graphics.RenderNode
import android.hardware.HardwareBuffer
import android.media.ImageReader
import android.util.Log

object HardwarePainter {
    @Volatile private var unavailable = false
    private val executor = java.util.concurrent.Executors.newSingleThreadExecutor { r -> Thread(r, "HardwarePainter").apply { isDaemon = true } }

    /**
     * Draws with [draw] on a hardware canvas of `width × height` and returns the pixels,
     * or null if the GPU path is unavailable (or hangs, as it does on some emulators:
     * after one timeout it is not tried again).
     */
    fun render(width: Int, height: Int, draw: (Canvas) -> Unit): Bitmap? {
        if (unavailable || width <= 0 || height <= 0) return null
        val future = executor.submit<Bitmap?> { renderNow(width, height, draw) }
        return try {
            future.get(2500, java.util.concurrent.TimeUnit.MILLISECONDS)
        } catch (e: java.util.concurrent.TimeoutException) {
            Log.e("CardFX", "hardware render timed out, falling back to the painted approximations")
            unavailable = true
            null
        } catch (e: Exception) {
            Log.e("CardFX", "hardware render failed: ${e.message}")
            null
        }
    }

    private fun renderNow(width: Int, height: Int, draw: (Canvas) -> Unit): Bitmap? {
        var reader: ImageReader? = null
        var renderer: HardwareRenderer? = null
        try {
            reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 1, HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE or HardwareBuffer.USAGE_GPU_COLOR_OUTPUT)
            renderer = HardwareRenderer()
            val node = RenderNode("generator")
            node.setPosition(0, 0, width, height)
            val canvas = node.beginRecording(width, height)
            draw(canvas)
            node.endRecording()
            renderer.setContentRoot(node)
            renderer.setSurface(reader.surface)
            renderer.createRenderRequest().setWaitForPresent(true).syncAndDraw()
            val image = reader.acquireNextImage() ?: return null
            val buffer = image.hardwareBuffer ?: run { image.close(); return null }
            val hardware = Bitmap.wrapHardwareBuffer(buffer, ColorSpace.get(ColorSpace.Named.SRGB))
            val copy = hardware?.copy(Bitmap.Config.ARGB_8888, false)
            hardware?.recycle()
            buffer.close()
            image.close()
            return copy
        } catch (e: Exception) {
            Log.e("CardFX", "hardware render failed: ${e.message}")
            return null
        } finally {
            renderer?.destroy()
            reader?.close()
        }
    }
}
