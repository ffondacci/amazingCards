// Card faces and the card back drawn with Canvas, following the four
// SwiftUI templates (creature, artist, painting, celestial) and
// CardBackView. Sizes scale with the card width like CardMetrics.
package com.amazingcards.cardkit.paint

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import com.amazingcards.cardkit.core.Card
import com.amazingcards.cardkit.core.CardColor
import com.amazingcards.cardkit.core.CardContent
import com.amazingcards.cardkit.core.CreatureElement
import com.amazingcards.cardkit.core.Rarity
import kotlin.math.max
import kotlin.math.min

/** Every dimension of a card relative to its width (CardMetrics). */
class CardMetrics(val width: Float, val height: Float, val cornerRadiusPercent: Float = 4.5f) {
    fun pt(percentOfWidth: Float) = width * percentOfWidth / 100
    fun ptH(percentOfHeight: Float) = height * percentOfHeight / 100
    val cornerRadius get() = pt(cornerRadiusPercent)
    val borderWidth get() = pt(4.1f)
    val shape: Path get() = roundedRect(RectF(0f, 0f, width, height), cornerRadius)
    fun innerShape(inset: Float): Path = roundedRect(RectF(inset, inset, width - inset, height - inset), max(cornerRadius - inset, pt(1f)))

    companion object { const val ASPECT_RATIO = 63f / 88f }
}

/** The back of every card (CardBackDesign.midnight). */
data class CardBackDesign(
    val colors: List<CardColor> = listOf(CardColor(0x141A3A), CardColor(0x2B1E5C)),
    val nebula: List<CardColor> = listOf(CardColor(0x6A3FD9), CardColor(0xC04BFF), CardColor(0x2A7BFF)),
    val title: String = "AMAZING CARDS",
    val borderColor: CardColor = CardColor.GOLD,
)

/**
 * A painted card face. Framed templates come in three layers so the foil
 * can be applied per region like the SwiftUI templates: the frame (border
 * and paper), the artwork in its window, and the overlay (text, badges).
 * Borderless templates are one layer. [flat] is everything composited.
 */
class CardFace(val width: Int, val height: Int, val frame: Bitmap?, val art: Bitmap?, val artRect: RectF?, val overlay: Bitmap) {
    val isLayered: Boolean get() = frame != null
    val flat: Bitmap by lazy {
        if (frame == null) overlay else Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { out ->
            val c = Canvas(out)
            c.drawBitmap(frame, 0f, 0f, null)
            if (art != null && artRect != null) c.drawBitmap(art, null, artRect, Paint(Paint.FILTER_BITMAP_FLAG))
            c.drawBitmap(overlay, 0f, 0f, null)
        }
    }
}

/** The canvases a template draws into: three for framed templates, one shared otherwise. */
internal class Layers(val width: Int, val height: Int, layered: Boolean) {
    val frameBitmap: Bitmap? = if (layered) Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888) else null
    val overlayBitmap: Bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val frame: Canvas = if (frameBitmap != null) Canvas(frameBitmap) else Canvas(overlayBitmap)
    val overlay: Canvas = Canvas(overlayBitmap)
    var artBitmap: Bitmap? = null
    var artRect: RectF? = null
    val layered = layered

    /** Draws the artwork of a framed template: into its own layer when layered, else straight onto the overlay. */
    fun art(rect: RectF, draw: (Canvas, RectF) -> Unit) {
        if (!layered) { draw(overlay, rect); return }
        val b = Bitmap.createBitmap(max(1, rect.width().toInt()), max(1, rect.height().toInt()), Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        c.translate(-rect.left, -rect.top)
        draw(c, rect)
        artBitmap = b; artRect = RectF(rect)
    }

    fun face(): CardFace = CardFace(width, height, frameBitmap, artBitmap, artRect, overlayBitmap)
}

class CardPainter(private val artwork: ArtworkResolver, private val context: android.content.Context? = null) {

    /** The face flattened, for prints. */
    fun front(card: Card, width: Int): Bitmap = face(card, width, layered = false).flat

    /** The face in layers, for the interactive card. */
    fun face(card: Card, width: Int, layered: Boolean = true): CardFace {
        val w = width.toFloat()
        val h = w / CardMetrics.ASPECT_RATIO
        val m = CardMetrics(w, h)
        val framed = card.content is CardContent.ArtistContent || card.content is CardContent.CreatureContent
        val layers = Layers(width, h.toInt(), layered && framed)
        for (c in listOf(layers.frame, layers.overlay)) { c.save(); c.clipPath(m.shape) }
        when (val content = card.content) {
            is CardContent.PaintingContent -> painting(layers.overlay, card, content, m)
            is CardContent.CelestialContent -> celestial(layers.overlay, card, content, m)
            is CardContent.ArtistContent -> artist(layers, card, content, m)
            is CardContent.CreatureContent -> creature(layers, card, content, m)
        }
        for (c in listOf(layers.frame, layers.overlay)) c.restore()
        layers.overlay.drawPath(m.shape, Ink.stroke(Ink.white(0.18), max(m.pt(0.35f), 0.5f)))
        return layers.face()
    }

    private val generators = HashMap<String, Bitmap?>()

    /** A procedural generator rendered on the GPU into a bitmap of `w × h`, or null below Android 13. */
    private fun generator(effect: com.amazingcards.cardkit.fx.CardEffect, w: Float, h: Float): Bitmap? {
        val ctx = context ?: return null
        val key = "$effect:${w.toInt()}x${h.toInt()}"
        return generators.getOrPut(key) {
            val shader = com.amazingcards.cardkit.fx.CardFXShaders.generator(ctx, effect, w, h) ?: return@getOrPut null
            HardwarePainter.render(w.toInt(), h.toInt()) { c -> c.drawRect(0f, 0f, w, h, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.shader = shader }) }
        }
    }

    fun back(width: Int, design: CardBackDesign = CardBackDesign()): Bitmap {
        val w = width.toFloat()
        val h = w / CardMetrics.ASPECT_RATIO
        val bitmap = Bitmap.createBitmap(width, h.toInt(), Bitmap.Config.ARGB_8888)
        val c = Canvas(bitmap)
        val m = CardMetrics(w, h)
        c.save(); c.clipPath(m.shape)
        c.drawRect(0f, 0f, w, h, Ink.linear(0f, 0f, 0f, h, design.colors.map { Ink.color(it) }.toIntArray()))
        // Nebula screened over the gradient, like CardBackView.
        val nebula = generator(com.amazingcards.cardkit.fx.CardEffect.Nebula(com.amazingcards.cardkit.fx.NebulaPalette.VIOLET, 0.9f), w, h)
        if (nebula != null) {
            c.drawBitmap(nebula, 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG).apply { blendMode = android.graphics.BlendMode.SCREEN; alpha = 230 })
        } else {
            val seed = SeededNoise(5)
            for (i in 0 until 14) {
                val color = design.nebula[i % design.nebula.size]
                val cx = seed.next() * w; val cy = seed.next() * h; val r = w * (0.18f + seed.next() * 0.3f)
                c.drawCircle(cx, cy, r, Ink.radial(cx, cy, r, intArrayOf(Ink.color(color, 0.28), Ink.color(color, 0.0))))
            }
            for (i in 0 until 90) {
                val x = seed.next() * w; val y = seed.next() * h; val r = 0.6f + seed.next() * 1.8f
                c.drawCircle(x, y, r * w / 640, Ink.fill(Ink.white(0.3 + seed.next() * 0.6)))
            }
        }
        c.drawPath(m.innerShape(m.pt(3.5f)), Ink.stroke(Ink.color(design.borderColor, 0.9), m.pt(0.7f)))
        c.drawPath(m.innerShape(m.pt(5.5f)), Ink.stroke(Ink.color(design.borderColor, 0.45), m.pt(0.3f)))
        val emblemR = m.pt(13f)
        val cy = h / 2 - m.ptH(2f)
        val emblem = Glyph.sparkle(w / 2, cy, emblemR)
        c.drawPath(emblem, Ink.fill(Ink.color(design.borderColor, 0.8)).apply { setShadowLayer(m.pt(3f), 0f, 0f, Ink.color(design.borderColor, 0.8)) })
        c.drawPath(emblem, Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = LinearGradient(0f, cy - emblemR, 0f, cy + emblemR, intArrayOf(Ink.color(design.borderColor), Color.WHITE), null, Shader.TileMode.CLAMP) })
        c.line(design.title, w / 2, cy + emblemR + m.ptH(2f), Ink.textPaint(m.pt(4.6f), Ink.color(design.borderColor), Weight.HEAVY, Family.ROUNDED, tracking = m.pt(1f)), Align.CENTER)
        c.restore()
        c.drawPath(m.shape, Ink.stroke(Ink.white(0.18), max(m.pt(0.35f), 0.5f)))
        return bitmap
    }

    // MARK: - Painting: borderless, caption fades in from the bottom.

    private fun painting(c: Canvas, card: Card, content: CardContent.PaintingContent, m: CardMetrics) {
        val p = content.painting
        val full = RectF(0f, 0f, m.width, m.height)
        artwork.bitmap(card.artwork, m.width.toInt(), m.height.toInt())?.let { c.drawCover(it, full) } ?: placeholder(c, full)
        val gradTop = m.height - m.ptH(42f)
        c.drawRect(0f, gradTop, m.width, m.height, Ink.linear(0f, gradTop, 0f, m.height, intArrayOf(Color.TRANSPARENT, Ink.black(0.55), Ink.black(0.92)), floatArrayOf(0f, 0.45f, 1f)))
        // Caption, laid out bottom-up: measure first.
        val x = m.pt(6f)
        val maxW = m.width - 2 * x
        val title = Ink.textPaint(m.pt(7f), Color.WHITE, Weight.SEMIBOLD, Family.SERIF)
        val byline = Ink.textPaint(m.pt(3.2f), Ink.white(0.9), Weight.MEDIUM, Family.SERIF)
        val medium = Ink.textPaint(m.pt(2.5f), Ink.white(0.7), Weight.REGULAR, Family.SERIF)
        val desc = Ink.textPaint(m.pt(2.6f), Ink.white(0.85), Weight.REGULAR, Family.SERIF)
        val scratch = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
        val measure = Canvas(scratch)
        val titleH = measure.paragraph(card.title, 0f, 0f, title, maxW, 2, 0.6f)
        val bylineH = measure.line("", 0f, 0f, byline)
        val mediumH = measure.line("", 0f, 0f, medium)
        val locationH = if (p.location != null) measure.line("", 0f, 0f, medium) else 0f
        val descH = measure.paragraph(p.description, 0f, 0f, desc, maxW, 3, 0.7f)
        val spacing = m.ptH(0.6f)
        val total = titleH + bylineH + mediumH + locationH + descH + spacing * 4 + m.ptH(0.5f)
        var y = m.height - m.ptH(4f) - total
        y += c.paragraph(card.title, x, y, title, maxW, 2, 0.6f) + spacing
        y += c.line("${p.artist}  ·  ${p.year}", x, y, byline) + spacing
        y += c.line(p.medium + (p.dimensions?.let { "  ·  $it" } ?: ""), x, y, medium) + spacing
        p.location?.let { loc ->
            val icon = m.pt(2.2f)
            c.drawPath(columns(x, y + icon * 0.15f, icon), Ink.fill(Ink.white(0.7)))
            y += c.line(loc, x + icon + m.pt(1f), y, medium) + spacing
        }
        y += m.ptH(0.5f)
        c.paragraph(p.description, x, y, desc, maxW, 3, 0.7f)
        topRight(c, card, m, m.pt(5f), Ink.white(0.85), Ink.black(0.35))
        c.drawPath(m.innerShape(m.pt(2f)), Ink.stroke(Ink.white(0.35), m.pt(0.35f)))
    }

    /** A tiny "building columns" glyph. */
    private fun columns(x: Float, y: Float, s: Float): Path = Path().apply {
        addRect(RectF(x, y, x + s, y + s * 0.18f), Path.Direction.CW)
        for (i in 0 until 3) addRect(RectF(x + s * (0.1f + i * 0.32f), y + s * 0.25f, x + s * (0.28f + i * 0.32f), y + s * 0.85f), Path.Direction.CW)
        addRect(RectF(x, y + s * 0.85f, x + s, y + s), Path.Direction.CW)
    }

    /** Set name pill on the left, number and rarity pill on the right. */
    private fun topRight(c: Canvas, card: Card, m: CardMetrics, pad: Float, text: Int, pill: Int) {
        card.setName?.let { set ->
            val paint = Ink.textPaint(m.pt(2.2f), text, Weight.SEMIBOLD, tracking = m.pt(0.3f))
            pillText(c, set.uppercase(), pad, pad, paint, m.pt(2f), m.pt(0.8f), pill)
        }
        val paint = Ink.textPaint(m.pt(2.4f), text, Weight.BOLD, Family.ROUNDED)
        val number = card.number?.formatted ?: ""
        val tw = paint.width(number)
        val sym = m.pt(2.6f)
        val fm = paint.fontMetrics
        val th = fm.descent - fm.ascent
        val px = m.pt(2f); val py = m.pt(0.8f)
        val w = tw + (if (number.isNotEmpty()) m.pt(0.8f) else 0f) + sym
        val rect = RectF(m.width - pad - w - 2 * px, pad, m.width - pad, pad + th + 2 * py)
        c.drawRoundRect(rect, rect.height() / 2, rect.height() / 2, Ink.fill(pill))
        if (number.isNotEmpty()) c.line(number, rect.left + px, rect.top + py, paint)
        rarity(c, card.rarity, rect.right - px - sym / 2, rect.centerY(), sym / 2)
    }

    private fun pillText(c: Canvas, text: String, x: Float, y: Float, paint: Paint, px: Float, py: Float, fill: Int): RectF {
        val tw = paint.width(text)
        val fm = paint.fontMetrics
        val th = fm.descent - fm.ascent
        val rect = RectF(x, y, x + tw + 2 * px, y + th + 2 * py)
        c.drawRoundRect(rect, rect.height() / 2, rect.height() / 2, Ink.fill(fill))
        c.line(text, x + px, y + py, paint)
        return rect
    }

    private fun rarity(c: Canvas, rarity: Rarity, cx: Float, cy: Float, r: Float) {
        c.drawPath(Glyph.rarity(rarity.ordinal, cx, cy, r), Ink.fill(Ink.color(rarity.color)).apply { setShadowLayer(r * 0.2f, 0f, 0f, Ink.black(0.3)) })
    }

    private fun placeholder(c: Canvas, rect: RectF) {
        c.drawRect(rect, Ink.fill(Color.BLACK))
        val nebula = generator(com.amazingcards.cardkit.fx.CardEffect.Nebula(com.amazingcards.cardkit.fx.NebulaPalette.VIOLET, 0.9f), rect.width(), rect.height())
        if (nebula != null) { c.drawBitmap(nebula, rect.left, rect.top, Paint(Paint.FILTER_BITMAP_FLAG)); return }
        val seed = SeededNoise(11)
        for (i in 0 until 10) {
            val cx = rect.left + seed.next() * rect.width(); val cy = rect.top + seed.next() * rect.height(); val r = rect.width() * (0.2f + seed.next() * 0.3f)
            val color = listOf(CardColor(0x6A3FD9), CardColor(0xC04BFF), CardColor(0x2A7BFF))[i % 3]
            c.drawCircle(cx, cy, r, Ink.radial(cx, cy, r, intArrayOf(Ink.color(color, 0.5), Ink.color(color, 0.0))))
        }
    }

    // MARK: - Celestial: photo over a star field, data grid.

    private fun celestial(c: Canvas, card: Card, content: CardContent.CelestialContent, m: CardMetrics) {
        val o = content.obj
        val accent = card.resolvedAccent
        c.drawRect(0f, 0f, m.width, m.height, Ink.fill(Color.BLACK))
        val field = generator(com.amazingcards.cardkit.fx.CardEffect.Starfield(34f, 1f), m.width, m.height)
        if (field != null) c.drawBitmap(field, 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG)) else {
            val seed = SeededNoise(34)
            for (i in 0 until 170) {
                val x = seed.next() * m.width; val y = seed.next() * m.height; val r = (0.4f + seed.next() * seed.next() * 1.6f) * m.width / 640
                c.drawCircle(x, y, r, Ink.fill(Ink.white(0.25 + seed.next() * 0.7)))
            }
        }
        val photoH = m.ptH(56f)
        val photo = RectF(0f, 0f, m.width, photoH)
        val layer = c.saveLayer(photo, null)
        artwork.bitmap(card.artwork, m.width.toInt(), photoH.toInt())?.let { c.drawCover(it, photo) } ?: placeholder(c, photo)
        c.drawRect(0f, photoH - m.ptH(18f), m.width, photoH, Ink.linear(0f, photoH - m.ptH(18f), 0f, photoH, intArrayOf(Color.TRANSPARENT, Color.BLACK)))
        val fade = Paint().apply {
            shader = LinearGradient(0f, 0f, 0f, photoH, intArrayOf(Color.BLACK, Color.BLACK, Color.TRANSPARENT), floatArrayOf(0f, 0.7f, 1f), Shader.TileMode.CLAMP)
            xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.DST_IN)
        }
        c.drawRect(photo, fade)
        c.restoreToCount(layer)

        val x = m.pt(6f)
        val maxW = m.width - 2 * x
        var y = photoH + m.ptH(0.5f)
        val title = Ink.textPaint(m.pt(6.6f), Color.WHITE, Weight.BOLD, Family.ROUNDED, tracking = m.pt(0.6f))
        val kindGlyph = m.pt(4.5f)
        y += c.line(card.title.uppercase(), x, y, title, maxWidth = maxW - kindGlyph - m.pt(2f), minScale = 0.5f)
        c.drawPath(Glyph.star(m.width - x - kindGlyph / 2, y - m.pt(3.6f), kindGlyph / 2), Ink.fill(Ink.color(accent)))
        y += m.ptH(1f)
        y += c.line(o.designation, x, y, Ink.textPaint(m.pt(3f), Ink.color(accent), Weight.MEDIUM, Family.MONO)) + m.ptH(1f)
        val pillFont = Ink.textPaint(m.pt(2.2f), Ink.color(accent), Weight.HEAVY, Family.ROUNDED)
        val r1 = pillText(c, o.kind.displayName.uppercase(), x, y, pillFont, m.pt(1.6f), m.pt(0.56f), Ink.color(accent, 0.22))
        pillText(c, o.constellation.uppercase(), r1.right + m.pt(1.5f), y, Ink.textPaint(m.pt(2.2f), Ink.white(0.85), Weight.HEAVY, Family.ROUNDED), m.pt(1.6f), m.pt(0.56f), Ink.white(0.12))
        y += r1.height() + m.ptH(1.5f)
        // Data grid: two columns.
        val colW = (maxW - m.pt(3f)) / 2
        val cells = mutableListOf<Pair<String, String>>("Distance" to o.distance)
        o.apparentMagnitude?.let { cells.add("Magnitude" to String.format("%.1f", it)) }
        o.apparentSize?.let { cells.add("Size" to it) }
        cells.add("Constellation" to o.constellation)
        var rowY = y
        for ((i, cell) in cells.withIndex()) {
            val cx = x + (i % 2) * (colW + m.pt(3f))
            val labelH = c.line(cell.first.uppercase(), cx, rowY, Ink.textPaint(m.pt(1.9f), Ink.white(0.5), Weight.SEMIBOLD, tracking = m.pt(0.2f)))
            val valueH = c.line(cell.second, cx, rowY + labelH, Ink.textPaint(m.pt(2.9f), Color.WHITE, Weight.SEMIBOLD, Family.MONO), maxWidth = colW, minScale = 0.6f)
            if (i % 2 == 1 || i == cells.size - 1) rowY += labelH + valueH + m.ptH(0.5f)
        }
        y = rowY + m.ptH(0.5f)
        c.paragraph(o.description, x, y, Ink.textPaint(m.pt(2.6f), Ink.white(0.8)), maxW, 4, 0.7f)
        // Footer.
        val footY = m.height - m.ptH(3.5f)
        card.credit?.let { c.line(it, x, footY - m.pt(2f) * 1.3f, Ink.textPaint(m.pt(2f), Ink.white(0.5))) }
        val num = Ink.textPaint(m.pt(2.4f), Ink.white(0.85), Weight.BOLD, Family.MONO)
        val sym = m.pt(2.4f)
        val number = card.number?.formatted ?: ""
        val nw = num.width(number)
        rarity(c, card.rarity, m.width - x - sym / 2, footY - sym * 0.7f, sym / 2)
        if (number.isNotEmpty()) c.line(number, m.width - x - sym - m.pt(0.8f) - nw, footY - m.pt(2.4f) * 1.3f, num)
        c.drawPath(m.innerShape(m.pt(2f)), Ink.stroke(Ink.color(accent, 0.6), m.pt(0.35f)))
    }

    // MARK: - Artist: framed portrait on holo paper.

    private fun artist(layers: Layers, card: Card, content: CardContent.ArtistContent, m: CardMetrics) {
        val a = content.artist
        val accent = card.resolvedAccent
        frame(layers.frame, m, intArrayOf(Ink.color(accent), Ink.color(accent, 0.7), Ink.color(accent)), accent.hue + 0.08, 0.9 * 0.85)
        layers.frame.drawPath(m.innerShape(m.pt(1.2f)), Ink.stroke(Ink.white(0.35), m.pt(0.5f)))
        val c = layers.overlay
        val inset = m.borderWidth + m.pt(1.2f)
        val left = inset; val right = m.width - inset
        val innerW = right - left
        var y = inset
        // Portrait with a soft accent halo, on the artwork layer.
        val portraitH = m.ptH(46f)
        layers.art(RectF(left, y, right, y + portraitH)) { ac, rect ->
            ac.drawRect(rect, Ink.radial(m.width / 2, rect.top + portraitH / 2, m.pt(40f), intArrayOf(Ink.color(accent, 0.35), Ink.color(accent, 0.0))))
            artwork.bitmap(card.artwork, innerW.toInt(), portraitH.toInt())?.let {
                val inner = RectF(rect.left + m.pt(3f), rect.top + m.pt(2f), rect.right - m.pt(3f), rect.bottom)
                val sx = inner.width() / it.width; val sy = inner.height() / it.height; val s = min(sx, sy)
                val dw = it.width * s; val dh = it.height * s
                val dst = RectF(inner.centerX() - dw / 2, inner.centerY() - dh / 2, inner.centerX() + dw / 2, inner.centerY() + dh / 2)
                ac.drawBitmap(it, null, dst, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
            }
        }
        y += portraitH - m.ptH(3f)
        // Banner.
        val bannerH = m.ptH(10f)
        val banner = RectF(left, y, right, y + bannerH)
        c.shadowed(roundedRect(banner, m.pt(2f)), Shadow(Ink.black(0.3), m.pt(1f), 0f, m.pt(0.5f)))
        c.drawRoundRect(banner, m.pt(2f), m.pt(2f), Ink.fill(Ink.color(accent)))
        val textColor = Ink.color(accent.contrastingText)
        val title = Ink.textPaint(m.pt(7.4f), textColor, Weight.BOLD, Family.SERIF)
        val sub = Ink.textPaint(m.pt(2.8f), Ink.color(accent.contrastingText, 0.8), Weight.MEDIUM, Family.SERIF)
        val th = title.fontMetrics.let { it.descent - it.ascent }; val sh = sub.fontMetrics.let { it.descent - it.ascent }
        var ty = banner.centerY() - (th + sh + m.ptH(0.2f)) / 2
        ty += c.line(card.title, m.width / 2, ty, title, Align.CENTER, innerW - m.pt(6f), 0.5f) + m.ptH(0.2f)
        c.line("${a.lifespan}  ·  ${a.nationality}", m.width / 2, ty, sub, Align.CENTER)
        y += bannerH + m.ptH(1.5f)
        // Details.
        val dx = left + m.pt(1.5f)
        val dw = innerW - m.pt(3f)
        val pill = pillText(c, a.movement.uppercase(), dx, y, Ink.textPaint(m.pt(2.4f), Ink.color(accent), Weight.HEAVY, Family.ROUNDED), m.pt(1.8f), m.pt(0.63f), Ink.color(accent, 0.18))
        y += pill.height() + m.ptH(1f)
        y += c.paragraph(a.biography, dx, y, Ink.textPaint(m.pt(2.9f), Ink.black(0.85), Weight.REGULAR, Family.SERIF), dw, 6, 0.7f) + m.ptH(1f)
        for (work in a.notableWorks.take(3)) {
            val g = m.pt(2.2f)
            c.drawPath(Glyph.palette(dx + g / 2, y + g * 0.7f, g / 2), Ink.fill(Ink.color(accent)))
            y += c.line(work, dx + g + m.pt(1.2f), y, Ink.textPaint(m.pt(2.7f), Ink.black(0.85), Weight.SEMIBOLD, Family.SERIF), maxWidth = dw - g - m.pt(1.2f), minScale = 0.6f) + m.ptH(0.3f)
        }
        a.quote?.let {
            y += m.ptH(0.5f)
            c.paragraph("“$it”", dx, y, Ink.textPaint(m.pt(2.6f), Ink.black(0.65), Weight.REGULAR, Family.SERIF, italic = true), dw, 2, 0.7f)
        }
        // Footer.
        val footTop = m.height - inset - m.ptH(5.5f)
        card.setName?.let { c.line(it.uppercase(), dx, footTop + m.ptH(5.5f) - m.pt(2f) * 1.4f, Ink.textPaint(m.pt(2f), Ink.black(0.55), Weight.SEMIBOLD)) }
        val num = Ink.textPaint(m.pt(2.4f), Ink.black(0.8), Weight.BOLD, Family.ROUNDED)
        val sym = m.pt(2.4f)
        val number = card.number?.formatted ?: ""
        val baseY = footTop + m.ptH(5.5f) - m.pt(2.4f) * 1.4f
        rarity(c, card.rarity, right - m.pt(1.5f) - sym / 2, baseY + sym * 0.75f, sym / 2)
        if (number.isNotEmpty()) c.line(number, right - m.pt(1.5f) - sym - m.pt(0.8f) - num.width(number), baseY, num)
    }

    /** Coloured frame with pastel holo paper inside, like `holoPaper`. */
    private fun frame(c: Canvas, m: CardMetrics, colors: IntArray, hue: Double, intensity: Double) {
        c.drawPath(m.shape, Ink.linear(0f, 0f, m.width, m.height, colors))
        val inner = m.innerShape(m.borderWidth)
        c.save(); c.clipPath(inner)
        val paper = generator(com.amazingcards.cardkit.fx.CardEffect.HoloPaper(hue.toFloat(), intensity.toFloat()), m.width, m.height)
        if (paper != null) { c.drawBitmap(paper, 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG)); c.restore(); return }
        val base = hsv(hue, 0.12 * intensity, 0.98)
        c.drawRect(0f, 0f, m.width, m.height, Ink.fill(base))
        // Pastel bands drifting across the paper.
        val bands = intArrayOf(hsv(hue + 0.08, 0.18 * intensity, 1.0, 0.55), hsv(hue + 0.45, 0.14 * intensity, 1.0, 0.0), hsv(hue + 0.72, 0.2 * intensity, 1.0, 0.5), hsv(hue + 0.3, 0.1 * intensity, 1.0, 0.0), hsv(hue + 0.55, 0.16 * intensity, 1.0, 0.45))
        c.drawRect(0f, 0f, m.width, m.height, Ink.linear(0f, 0f, m.width, m.height * 0.6f, bands))
        c.restore()
    }

    private fun hsv(hue: Double, s: Double, v: Double, alpha: Double = 1.0): Int {
        val h = ((hue % 1.0) + 1.0) % 1.0
        return Color.HSVToColor((alpha * 255).toInt(), floatArrayOf((h * 360).toFloat(), s.toFloat(), v.toFloat()))
    }

    // MARK: - Creature: classic framed trading card.

    private fun creature(layers: Layers, card: Card, content: CardContent.CreatureContent, m: CardMetrics) {
        val cr = content.creature
        val accent = cr.element.color
        frame(layers.frame, m, intArrayOf(Ink.color(CardColor(0xF7DC7A)), Ink.color(CardColor(0xE9C44B))), accent.hue, 0.9)
        val c = layers.overlay
        val left = m.pt(7.8f); val right = m.width - left
        var y = m.ptH(3.4f)
        // Header.
        val headerH = m.ptH(6.5f)
        val stage = pillText(c, cr.stage.uppercase(), left + m.pt(1f), y + headerH / 2 - m.pt(2.6f) * 0.9f, Ink.textPaint(m.pt(2.6f), Color.WHITE, Weight.HEAVY, Family.ROUNDED), m.pt(1.6f), m.pt(0.56f), Ink.black(0.85))
        val icon = m.pt(6.4f)
        elementIcon(c, cr.element, right - m.pt(1f) - icon / 2, y + headerH / 2, icon)
        val hpBig = Ink.textPaint(m.pt(6.5f), Color.BLACK, Weight.HEAVY, Family.ROUNDED)
        val hpSmall = Ink.textPaint(m.pt(2.4f), Color.BLACK, Weight.BOLD, Family.ROUNDED)
        val hpW = hpBig.width("${cr.hitPoints}")
        val hpX = right - m.pt(1f) - icon - m.pt(2f) - hpW
        val bigH = hpBig.fontMetrics.let { it.descent - it.ascent }
        c.line("${cr.hitPoints}", hpX, y + headerH / 2 - bigH / 2, hpBig)
        c.line("HP", hpX - m.pt(0.6f) - hpSmall.width("HP"), y + headerH / 2 + bigH / 2 - hpSmall.fontMetrics.let { it.descent - it.ascent } - m.pt(1.2f), hpSmall)
        val title = Ink.textPaint(m.pt(7f), Color.BLACK, Weight.HEAVY, Family.ROUNDED)
        val titleH = title.fontMetrics.let { it.descent - it.ascent }
        c.line(card.title, stage.right + m.pt(2f), y + headerH / 2 - titleH / 2, title, maxWidth = hpX - m.pt(2f) - stage.right - m.pt(2f), minScale = 0.5f)
        y += headerH
        // Artwork window.
        val winH = m.ptH(37.4f)
        val window = RectF(left, y, right, y + winH)
        layers.frame.shadowed(Path().apply { addRect(window, Path.Direction.CW) }, Shadow(Ink.black(0.35), m.pt(0.8f), 0f, m.pt(0.4f)))
        layers.art(window) { ac, rect -> artwork.bitmap(card.artwork, rect.width().toInt(), winH.toInt())?.let { ac.drawCover(it, rect) } ?: placeholder(ac, rect) }
        c.drawRect(window, Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = m.pt(0.9f); shader = LinearGradient(window.left, window.top, window.right, window.bottom, intArrayOf(Ink.rgb(0.95, 0.95, 0.95), Ink.rgb(0.55, 0.55, 0.55), Ink.rgb(0.9, 0.9, 0.9)), null, Shader.TileMode.CLAMP) })
        y += winH + m.ptH(0.4f)
        // Species strip.
        val stripH = m.ptH(2.8f)
        c.drawPath(slanted(RectF(left + m.pt(3f), y, right - m.pt(3f), y + stripH), 0.9f), Ink.linear(left, 0f, right, 0f, intArrayOf(Ink.rgb(0.98, 0.98, 0.98), Ink.rgb(0.78, 0.78, 0.78), Ink.rgb(0.96, 0.96, 0.96))))
        val species = Ink.textPaint(m.pt(2.4f), Ink.black(0.8), Weight.MEDIUM, Family.ROUNDED, italic = true)
        c.line(cr.species, m.width / 2, y + stripH / 2 - species.fontMetrics.let { it.descent - it.ascent } / 2, species, Align.CENTER, right - left - m.pt(12f), 0.6f)
        y += stripH + m.ptH(1.2f)
        // Attacks.
        for (attack in cr.attacks) {
            val costW = m.pt(16f)
            var cx = left
            for (e in attack.cost) { elementIcon(c, e, cx + m.pt(2.5f), y + m.pt(2.5f), m.pt(5f)); cx += m.pt(5.4f) }
            val name = Ink.textPaint(m.pt(5f), Color.BLACK, Weight.HEAVY, Family.ROUNDED)
            val dmg = Ink.textPaint(m.pt(6f), Color.BLACK, Weight.HEAVY, Family.ROUNDED)
            val dmgText = attack.damage?.toString() ?: ""
            val dmgW = max(dmg.width(dmgText), m.pt(10f))
            val nameX = left + max(costW, cx - left) + m.pt(1.5f)
            val nameMax = right - dmgW - m.pt(1.5f) - nameX
            val rowH = m.pt(5f)
            c.line(attack.name, nameX + nameMax / 2, y + rowH / 2 - name.fontMetrics.let { it.descent - it.ascent } / 2, name, Align.CENTER, nameMax, 0.5f)
            if (dmgText.isNotEmpty()) c.line(dmgText, right, y + rowH / 2 - dmg.fontMetrics.let { it.descent - it.ascent } / 2, dmg, Align.RIGHT)
            y += rowH + m.ptH(0.3f)
            attack.text?.let { y += c.paragraph(it, left, y, Ink.textPaint(m.pt(2.6f), Ink.black(0.9)), right - left, 3, 0.7f) }
            y += m.ptH(1.2f)
        }
        // Stats row and footer, from the bottom.
        val footerH = m.ptH(8f)
        val statsH = m.ptH(3.4f)
        val footerTop = m.height - m.ptH(1.2f) - footerH
        val statsTop = footerTop - m.ptH(0.6f) - statsH
        val boxW = (right - left - 2 * m.pt(1.5f)) / 3
        val labels = listOf("weakness", "resistance", "retreat")
        for (i in 0 until 3) {
            val bx = left + i * (boxW + m.pt(1.5f))
            val box = RectF(bx, statsTop, bx + boxW, statsTop + statsH)
            c.drawPath(slanted(box, 0.7f), Ink.fill(Ink.white(0.85)))
            val label = Ink.textPaint(m.pt(2.2f), Ink.black(0.75), Weight.SEMIBOLD, Family.ROUNDED)
            val lh = label.fontMetrics.let { it.descent - it.ascent }
            c.line(labels[i], bx + m.pt(2f), box.centerY() - lh / 2, label)
            var vx = bx + m.pt(2f) + label.width(labels[i]) + m.pt(1f)
            val value = Ink.textPaint(m.pt(3f), Color.BLACK, Weight.HEAVY, Family.ROUNDED)
            when (i) {
                0 -> cr.weakness?.let { elementIcon(c, it, vx + m.pt(1.6f), box.centerY(), m.pt(3.2f)); c.line("×2", vx + m.pt(3.2f) + m.pt(1f), box.centerY() - value.fontMetrics.let { f -> f.descent - f.ascent } / 2, value) }
                1 -> cr.resistance?.let { elementIcon(c, it, vx + m.pt(1.6f), box.centerY(), m.pt(3.2f)); c.line("−30", vx + m.pt(3.2f) + m.pt(1f), box.centerY() - value.fontMetrics.let { f -> f.descent - f.ascent } / 2, value) }
                else -> repeat(max(cr.retreatCost, 0)) { elementIcon(c, CreatureElement.COLORLESS, vx + m.pt(1.6f), box.centerY(), m.pt(3.2f)); vx += m.pt(3.5f) }
            }
        }
        var fy = footerTop
        card.credit?.let { fy += c.line("Illus. $it", left, fy, Ink.textPaint(m.pt(2.2f), Ink.black(0.85), Weight.MEDIUM, italic = true)) + m.ptH(0.3f) }
        val num = Ink.textPaint(m.pt(2.4f), Ink.black(0.85), Weight.BOLD, Family.ROUNDED)
        val number = card.number?.formatted ?: ""
        val nh = c.line(number, left, fy, num)
        rarity(c, card.rarity, left + num.width(number) + m.pt(0.8f) + m.pt(1.2f), fy + nh / 2, m.pt(1.2f))
        fy += nh + m.ptH(0.3f)
        card.setName?.let { c.line(it, left, fy, Ink.textPaint(m.pt(1.9f), Ink.black(0.6))) }
        cr.flavorText?.let { c.paragraph(it, right, footerTop + m.ptH(1f), Ink.textPaint(m.pt(2.1f), Ink.black(0.8), italic = true), m.pt(50f), 3, 0.7f, Align.RIGHT) }
    }

    private fun slanted(r: RectF, slant: Float): Path = Path().apply {
        val dx = r.height() * slant
        moveTo(r.left + dx, r.top); lineTo(r.right, r.top); lineTo(r.right - dx, r.bottom); lineTo(r.left, r.bottom); close()
    }

    /** Circular energy icon of an element. */
    private fun elementIcon(c: Canvas, element: CreatureElement, cx: Float, cy: Float, d: Float) {
        val color = element.color
        c.drawCircle(cx, cy, d / 2, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = RadialGradient(cx - d * 0.35f, cy - d * 0.35f, d, intArrayOf(Ink.color(color, 0.95), Ink.color(color, 0.7)), null, Shader.TileMode.CLAMP)
            setShadowLayer(d * 0.08f, 0f, d * 0.05f, Ink.black(0.25))
        })
        c.drawCircle(cx, cy, d / 2 - d * 0.035f, Ink.stroke(Ink.white(0.9), d * 0.07f))
        c.drawPath(Glyph.star(cx, cy, d * 0.26f), Ink.fill(Ink.color(color.contrastingText)))
    }
}

/** Tiny LCG for repeatable scatter. */
internal class SeededNoise(seed: Int) {
    private var state = seed.toLong() and 0xFFFFFFFFL
    fun next(): Float { state = (state * 1664525L + 1013904223L) and 0xFFFFFFFFL; return (state shr 8).toFloat() / (1 shl 24).toFloat() }
}
