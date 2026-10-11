// The app's own artworks drawn with Canvas: an aurora and a comet, both
// reachable from any card or pack through `CardArtwork.Custom`.
package com.amazingcards.demo

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import com.amazingcards.cardkit.paint.ArtworkProvider
import kotlin.math.PI
import kotlin.math.sin

object CustomArtworks {
    const val AURORA = "aurora"
    const val COMET = "canvas-comet"

    val provider = ArtworkProvider { key, width, height ->
        when (key) {
            AURORA -> aurora(width, height)
            COMET -> comet(640, 900)
            else -> null
        }
    }

    private fun argb(r: Double, g: Double, b: Double, a: Double = 1.0) = Color.argb((a * 255).toInt(), (r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt())

    /** Northern lights over a dark sea: a night gradient, three curtains of light and a sprinkle of stars. */
    fun aurora(width: Int, height: Int): Bitmap {
        val w = width.toFloat(); val h = height.toFloat()
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val c = Canvas(bitmap)
        c.drawRect(0f, 0f, w, h, Paint().apply { shader = LinearGradient(0f, 0f, 0f, h, intArrayOf(argb(0.02, 0.03, 0.1), argb(0.0, 0.07, 0.14), argb(0.0, 0.02, 0.05)), null, Shader.TileMode.CLAMP) })
        var seed = 7L
        fun next(): Float { seed = (seed * 1664525L + 1013904223L) and 0xFFFFFFFFL; return (seed shr 8).toFloat() / (1 shl 24) }
        val star = Paint(Paint.ANTI_ALIAS_FLAG)
        for (i in 0 until 140) {
            val x = next() * w; val y = next() * h * 0.7f; val r = 0.4f + next() * 1.4f
            star.color = Color.argb(((0.35 + next() * 0.6) * 255).toInt(), 255, 255, 255)
            c.drawOval(RectF(x, y, x + r, y + r), star)
        }
        val tints = listOf(argb(0.2, 1.0, 0.6), argb(0.35, 0.8, 1.0), argb(0.8, 0.4, 1.0))
        for ((index, tint) in tints.withIndex()) {
            val path = Path()
            val base = h * (0.42f + index * 0.08f)
            path.moveTo(-w * 0.1f, base)
            var x = -w * 0.1f
            while (x <= w * 1.1f) {
                val wave = sin(x / w * PI * (2.2 + index * 0.7) + index).toFloat() * h * 0.05f
                path.lineTo(x, base + wave)
                x += w * 0.02f
            }
            path.lineTo(w * 1.1f, -h * 0.1f); path.lineTo(-w * 0.1f, -h * 0.1f); path.close()
            val a0 = tint and 0x00FFFFFF
            c.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = LinearGradient(0f, 0f, 0f, base, intArrayOf(a0, a0 or (0x2E shl 24), a0 or (0xBF shl 24)), floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP)
            })
        }
        val sea = RectF(0f, h * 0.72f, w, h)
        c.drawRect(sea, Paint().apply { shader = LinearGradient(0f, sea.top, 0f, sea.bottom, intArrayOf(argb(0.05, 0.25, 0.3, 0.8), argb(0.0, 0.02, 0.05)), null, Shader.TileMode.CLAMP) })
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = w * 0.11f; typeface = Typeface.create("sans-serif-black", Typeface.NORMAL); color = Color.argb(217, 255, 255, 255)
            letterSpacing = 0.02f / 0.11f; textAlign = Paint.Align.CENTER; setShadowLayer(w * 0.03f, 0f, 0f, argb(0.2, 1.0, 0.6, 0.8))
        }
        c.drawText("AURORA", w / 2, h * 0.86f + text.textSize * 0.35f, text)
        return bitmap
    }

    /** A comet: a violet sky, a radial tail and a glowing head, with a label. */
    fun comet(width: Int, height: Int): Bitmap {
        val w = width.toFloat(); val h = height.toFloat()
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val c = Canvas(bitmap)
        c.drawRect(0f, 0f, w, h, Paint().apply { shader = LinearGradient(0f, 0f, 0f, h, intArrayOf(argb(0.04, 0.0, 0.1), argb(0.12, 0.02, 0.2), Color.BLACK), null, Shader.TileMode.CLAMP) })
        c.save()
        c.rotate(20f, w * 0.62f, h * 0.4f)
        c.drawRect(-w, -h, 2 * w, 2 * h, Paint().apply {
            shader = RadialGradient(w * 0.62f, h * 0.4f, w * 0.9f, intArrayOf(argb(0.6, 0.9, 1.0, 0.9), argb(0.3, 0.6, 1.0, 0.25), Color.TRANSPARENT), floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
        })
        c.restore()
        val r = w * 0.07f
        c.drawCircle(w * 0.62f, h * 0.4f, r, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; setShadowLayer(r, 0f, 0f, argb(0.7, 0.9, 1.0)) })
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = w * 0.1f; typeface = Typeface.create("sans-serif-black", Typeface.NORMAL); color = Color.argb(217, 255, 255, 255); textAlign = Paint.Align.CENTER }
        c.drawText("CANVAS", w / 2, h * 0.86f + text.textSize * 0.35f, text)
        return bitmap
    }
}
