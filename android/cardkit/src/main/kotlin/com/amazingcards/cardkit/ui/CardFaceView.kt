// A card drawn from its painted layers with the finish's shader passes
// applied per region, like CardView + CardFaceView in SwiftUI. Everything
// is drawn on the Compose canvas with AGSL paints: no render effects.
package com.amazingcards.cardkit.ui

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.BlendMode
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import com.amazingcards.cardkit.core.Card
import com.amazingcards.cardkit.fx.CardEffect
import com.amazingcards.cardkit.fx.CardFXShaders
import com.amazingcards.cardkit.fx.CardMotion
import com.amazingcards.cardkit.fx.FinishRecipe
import com.amazingcards.cardkit.paint.CardFace
import com.amazingcards.cardkit.paint.CardMetrics

/**
 * The face of a card with its finish. [face] comes from `PackPrints.cardLayers`;
 * the frame, the artwork and the whole card each get the passes of the recipe.
 */
@Composable
fun CardFaceView(card: Card, face: CardFace, motion: CardMotion, showsFinish: Boolean = true, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val recipe = if (showsFinish) FinishRecipe.recipe(card.finish, card.template) else FinishRecipe.NONE
    val paint = remember { Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG) }
    val matrix = remember { Matrix() }
    val clip = remember { Path() }
    Canvas(modifier.aspectRatio(CardMetrics.ASPECT_RATIO)) {
        val w = size.width; val h = size.height
        val native = drawContext.canvas.nativeCanvas
        val scale = w / face.width
        val radius = w * 4.5f / 100f
        clip.reset(); clip.addRoundRect(RectF(0f, 0f, w, h), radius, radius, Path.Direction.CW)

        fun layer(bitmap: Bitmap, rect: RectF, effects: List<CardEffect>) {
            // The passes compute uv from the canvas position, so a layer that sits
            // away from the origin is drawn in a translated frame; the bitmap's
            // local matrix must be final before it is chained, because
            // setInputShader captures the child's native instance right away.
            val offset = rect.left != 0f || rect.top != 0f
            matrix.reset()
            matrix.setScale(rect.width() / bitmap.width, rect.height() / bitmap.height)
            if (!offset) matrix.postTranslate(rect.left, rect.top)
            val input = BitmapShader(bitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply { setLocalMatrix(matrix) }
            val chained = CardFXShaders.chain(context, effects, input, motion, rect.width(), rect.height())
            paint.shader = chained ?: input
            paint.blendMode = null
            if (offset) {
                native.save(); native.translate(rect.left, rect.top)
                native.drawRect(0f, 0f, rect.width(), rect.height(), paint)
                native.restore()
            } else {
                native.drawRect(rect, paint)
            }
        }

        val full = RectF(0f, 0f, w, h)
        val regional = recipe.frame.isNotEmpty() || recipe.artwork.isNotEmpty()
        if (face.isLayered && face.frame != null && regional) {
            layer(face.frame, full, recipe.frame)
            val art = face.art; val artRect = face.artRect
            if (art != null && artRect != null) {
                layer(art, RectF(artRect.left * scale, artRect.top * scale, artRect.right * scale, artRect.bottom * scale), recipe.artwork)
            }
            layer(face.overlay, full, emptyList())
            // Framed cards only carry a glare over the whole card: an exact SCREEN overlay.
            for (effect in recipe.fullCard) {
                if (effect !is CardEffect.Glare) continue
                val overlay = CardFXShaders.glareOverlay(context, effect, motion, w, h) ?: continue
                paint.shader = overlay
                paint.blendMode = BlendMode.SCREEN
                native.save(); native.clipPath(clip)
                native.drawRect(full, paint)
                native.restore()
                paint.blendMode = null
            }
        } else {
            // One layer (borderless templates, or a foil over the whole framed card): the composite goes through the chain.
            layer(if (face.isLayered) face.flat else face.overlay, full, recipe.fullCard + recipe.artwork)
        }
        paint.shader = null
    }
}

/** The back of a card. */
@Composable
fun CardBackView(back: Bitmap, modifier: Modifier = Modifier) {
    Image(back.asImageBitmap(), "Card back", modifier.aspectRatio(CardMetrics.ASPECT_RATIO).fillMaxWidth(), contentScale = ContentScale.FillBounds)
}

/** Front or back with a 3D flip. */
@Composable
fun FlippableCard(card: Card, face: CardFace, back: Bitmap, isFaceUp: Boolean, motion: CardMotion, modifier: Modifier = Modifier) {
    val angle by animateFloatAsState(if (isFaceUp) 0f else 180f, spring(dampingRatio = 0.7f, stiffness = 180f), label = "flip")
    Box(modifier.aspectRatio(CardMetrics.ASPECT_RATIO).graphicsLayer { rotationY = angle; cameraDistance = 12f * density }) {
        if (angle <= 90f) {
            CardFaceView(card, face, motion, modifier = Modifier.fillMaxSize())
        } else {
            CardBackView(back, Modifier.fillMaxSize().graphicsLayer { rotationY = 180f })
        }
    }
}
