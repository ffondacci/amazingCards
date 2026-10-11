// A picture (or a plain black surface for generators) drawn through a
// chain of card effects, for catalogs and playgrounds.
package com.amazingcards.cardkit.ui

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import com.amazingcards.cardkit.fx.CardEffect
import com.amazingcards.cardkit.fx.CardFXShaders
import com.amazingcards.cardkit.fx.CardMotion
import com.amazingcards.cardkit.paint.CardMetrics

/**
 * Draws [picture] (a flat card face) or, when null, an opaque black card
 * shape, through [effects] driven by [motion]. Clipped to the card corners.
 */
@Composable
fun EffectSurface(picture: Bitmap?, effects: List<CardEffect>, motion: CardMotion, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val paint = remember { Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG) }
    val matrix = remember { Matrix() }
    val clip = remember { Path() }
    Canvas(modifier.aspectRatio(CardMetrics.ASPECT_RATIO)) {
        val w = size.width; val h = size.height
        val native = drawContext.canvas.nativeCanvas
        val radius = w * 4.5f / 100f
        clip.reset(); clip.addRoundRect(RectF(0f, 0f, w, h), radius, radius, Path.Direction.CW)
        val dpi = density
        // The passes work in dp: the picture maps dp to its pixels.
        val dpInput: Shader = if (picture != null) {
            matrix.reset(); matrix.setScale(w / dpi / picture.width, h / dpi / picture.height)
            BitmapShader(picture, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply { setLocalMatrix(matrix) }
        } else {
            LinearGradient(0f, 0f, 1f, 0f, intArrayOf(Color.BLACK, Color.BLACK), null, Shader.TileMode.CLAMP)
        }
        val plain: Shader = if (picture != null) {
            matrix.reset(); matrix.setScale(w / picture.width, h / picture.height)
            BitmapShader(picture, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply { setLocalMatrix(matrix) }
        } else dpInput
        paint.shader = CardFXShaders.chain(context, effects, dpInput, motion, w / dpi, h / dpi, dpi) ?: plain
        native.save(); native.clipPath(clip)
        native.drawRect(0f, 0f, w, h, paint)
        native.restore()
        paint.shader = null
    }
}
