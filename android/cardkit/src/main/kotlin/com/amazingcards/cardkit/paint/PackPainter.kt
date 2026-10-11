// Printed sides of a booster, drawn with Canvas the way BoosterPackView
// (forPrint) and PackBackView draw them in SwiftUI. Also the foil masks
// (red = foil, green = holo, blue = matte) the stage reads.
package com.amazingcards.cardkit.paint

import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import com.amazingcards.cardkit.core.CardColor
import com.amazingcards.cardkit.core.PackDesign
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sin

class PackPainter(private val artwork: ArtworkResolver) {

    /** Mask colour of a part of the print. */
    private fun mask(foil: Double, holo: Double, matte: Double) = Ink.rgb(foil, holo, matte)

    private class Palette(
        val top: IntArray, val bottom: IntArray, val pattern: Int, val accent: Int, val text: Int, val dimText: Int,
        val badgeFill: Int, val badgeStroke: Int, val seam: Int, val seamLight: Int, val titleTop: Int, val titleBottom: Int,
        val plateFill: Int, val plateStroke: Int, val plateText: Int,
    )

    private fun palette(d: PackDesign, asMask: Boolean): Palette {
        if (asMask) {
            val foil = mask(1.0, 1.0, 0.0); val chrome = mask(1.0, 0.35, 0.0); val ink = mask(0.15, 0.0, 0.4)
            return Palette(intArrayOf(foil, foil), intArrayOf(foil, foil), foil, chrome, chrome, chrome, ink, chrome, chrome, chrome, chrome, chrome, chrome, chrome, ink)
        }
        return Palette(
            intArrayOf(Ink.color(d.topColor, 0.95), Ink.color(d.topColor)), intArrayOf(Ink.color(d.bottomColor), Ink.color(d.bottomColor, 0.85)),
            Ink.white(0.08), Ink.color(d.accent), Color.WHITE, Ink.white(0.8), Ink.black(0.6), Ink.white(0.5),
            Ink.color(d.accent), Ink.white(0.85), Color.WHITE, Ink.color(d.accent, 0.85), Ink.color(d.accent), Ink.white(0.7), Color.WHITE,
        )
    }

    /** The front of the wrapper, `width` pixels wide in the pouch proportions. */
    fun front(design: PackDesign, width: Int, asMask: Boolean): Bitmap {
        val w = width.toFloat()
        val h = w / PackDesign.ASPECT_RATIO
        val bitmap = Bitmap.createBitmap(width, h.toInt(), Bitmap.Config.ARGB_8888)
        val c = Canvas(bitmap)
        val ink = palette(design, asMask)
        val top = h * design.stripFraction
        val bottom = h * design.bottomFraction
        val full = RectF(0f, 0f, w, h)

        // Full-bleed cover.
        if (asMask) {
            c.drawRect(full, Ink.fill(mask(0.3, 0.12, 0.1)))
        } else {
            val cover = artwork.bitmap(design.cover, width, h.toInt())
            if (cover != null) c.drawCover(cover, full) else c.drawRect(full, Ink.fill(Ink.rgb(0.25, 0.2, 0.4)))
        }

        // Top band.
        val topRect = RectF(0f, 0f, w, top)
        c.drawRect(topRect, Ink.linear(0f, 0f, 0f, top, ink.top))
        c.emblemPattern(design.emblem, topRect, w * 0.16f, ink.pattern)
        run {
            val shadow = if (asMask) null else Shadow(Ink.black(0.35), top * 0.03f, 0f, top * 0.02f)
            val brand = Ink.textPaint(top * 0.21f, ink.text, Weight.BLACK, Family.ROUNDED, tracking = top * 0.02f)
            val emblemR = top * 0.3f * 0.5f
            val gap = w * 0.025f
            val brandW = brand.width(design.brand)
            val blockW = emblemR * 2 + gap + brandW
            val maxW = w * 0.6f
            val scale = if (blockW > maxW) max(0.6f, maxW / blockW) else 1f
            brand.textSize *= scale
            val bw = brand.width(design.brand)
            val er = emblemR * scale
            val lineH = brand.fontMetrics.let { it.descent - it.ascent }
            val y0 = top * 0.16f
            val x0 = (w - (er * 2 + gap + bw)) / 2
            val cy = y0 + lineH / 2
            val emblemPaint = Ink.fill(ink.accent).apply { if (!asMask) setShadowLayer(top * 0.08f, 0f, 0f, Ink.color(design.accent, 0.8)) }
            c.drawPath(Glyph.emblem(design.emblem, x0 + er, cy, er), emblemPaint)
            c.line(design.brand, x0 + er * 2 + gap, y0, brand, shadow = shadow)
            val cards = Ink.textPaint(top * 0.12f, ink.dimText, Weight.BOLD, Family.ROUNDED, tracking = top * 0.03f)
            c.line("${design.cardCount} CARDS", w / 2, y0 + lineH + top * 0.02f, cards, Align.CENTER, shadow = shadow)
        }
        design.setCode?.let { code ->
            val paint = Ink.textPaint(top * 0.17f, ink.text, Weight.HEAVY, Family.ROUNDED)
            val tw = paint.width(code)
            val fm = paint.fontMetrics
            val th = fm.descent - fm.ascent
            val px = top * 0.12f; val py = top * 0.05f
            val right = w - w * 0.04f
            val rect = RectF(right - tw - 2 * px, top * 0.24f, right, top * 0.24f + th + 2 * py)
            val r = top * 0.08f
            c.drawRoundRect(rect, r, r, Ink.fill(ink.badgeFill))
            c.drawRoundRect(rect, r, r, Ink.stroke(ink.badgeStroke, 1f))
            c.line(code, rect.left + px, rect.top + py, paint)
        }

        // Bottom band with a soft top edge.
        run {
            val rect = RectF(0f, h - bottom, w, h)
            val layer = c.saveLayer(rect, null)
            c.drawRect(rect, Ink.linear(0f, rect.top, 0f, rect.bottom, ink.bottom))
            c.emblemPattern(design.emblem, rect, w * 0.16f, if (asMask) ink.pattern else Ink.white(0.06))
            val fade = Paint().apply {
                shader = LinearGradient(0f, rect.top, 0f, rect.top + rect.height() * 0.3f, intArrayOf(Color.TRANSPARENT, Color.BLACK), null, Shader.TileMode.CLAMP)
                xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.DST_IN)
            }
            c.drawRect(rect, fade)
            c.restoreToCount(layer)
        }

        // Seam: a bright double line where the top band is sealed.
        run {
            val seamH = max(w * 0.008f, 1.5f)
            val seam = RectF(0f, top, w, top + seamH)
            if (!asMask) c.drawRect(seam, Ink.fill(Ink.color(design.accent, 0.9)).apply { maskFilter = BlurMaskFilter(w * 0.012f, BlurMaskFilter.Blur.NORMAL) })
            c.drawRect(seam, Ink.fill(ink.seam))
            val gap = max(w * 0.006f, 1f)
            c.drawRect(RectF(0f, top + seamH + gap, w, top + seamH + gap + max(w * 0.004f, 1f)), Ink.fill(ink.seamLight))
        }

        // Set name and plate over the bottom of the cover.
        run {
            var y = h - bottom - h * 0.19f
            val title = Ink.textPaint(w * 0.12f, ink.titleTop, Weight.BLACK, Family.ROUNDED, tracking = w * 0.004f)
            val text = design.title.uppercase()
            val tw = title.width(text)
            val maxW = w * 0.92f
            if (tw > maxW) title.textSize = max(title.textSize * 0.5f, title.textSize * maxW / tw)
            val fm = title.fontMetrics
            val lineH = fm.descent - fm.ascent
            title.shader = LinearGradient(0f, y, 0f, y + lineH, intArrayOf(ink.titleTop, ink.titleBottom), null, Shader.TileMode.CLAMP)
            if (!asMask) {
                c.line(text, w / 2, y, Ink.textPaint(title.textSize, Ink.color(design.accent, 0.5), Weight.BLACK, Family.ROUNDED, tracking = w * 0.004f).apply { maskFilter = BlurMaskFilter(w * 0.03f, BlurMaskFilter.Blur.NORMAL) }, Align.CENTER)
                c.line(text, w / 2, y + w * 0.008f, Ink.textPaint(title.textSize, Ink.black(0.7), Weight.BLACK, Family.ROUNDED, tracking = w * 0.004f).apply { maskFilter = BlurMaskFilter(w * 0.012f, BlurMaskFilter.Blur.NORMAL) }, Align.CENTER)
            }
            c.line(text, w / 2, y, title, Align.CENTER)
            y += lineH + h * 0.008f
            design.subtitle?.let { sub ->
                val paint = Ink.textPaint(w * 0.055f, ink.plateText, Weight.HEAVY, Family.ROUNDED)
                val sw = paint.width(sub)
                val sfm = paint.fontMetrics
                val sh = sfm.descent - sfm.ascent
                val px = w * 0.06f; val py = w * 0.012f
                val rect = RectF(w / 2 - sw / 2 - px, y, w / 2 + sw / 2 + px, y + sh + 2 * py)
                val plate = namePlate(rect)
                if (!asMask) c.shadowed(plate, Shadow(Ink.black(0.5), w * 0.01f, 0f, w * 0.006f))
                c.drawPath(plate, Ink.fill(ink.plateFill))
                c.drawPath(plate, Ink.stroke(ink.plateStroke, max(w * 0.004f, 1f)))
                c.line(sub, w / 2, y + py, paint, Align.CENTER)
            }
        }
        return bitmap
    }

    /** Hexagonal plate holding the pack name. */
    private fun namePlate(r: RectF): Path = Path().apply {
        val cut = r.height() * 0.5f
        moveTo(r.left + cut, r.top); lineTo(r.right - cut, r.top); lineTo(r.right, r.centerY())
        lineTo(r.right - cut, r.bottom); lineTo(r.left + cut, r.bottom); lineTo(r.left, r.centerY()); close()
    }

    /** The back of the wrapper. */
    fun back(design: PackDesign, width: Int, asMask: Boolean): Bitmap {
        val w = width.toFloat()
        val h = w / PackDesign.ASPECT_RATIO
        val bitmap = Bitmap.createBitmap(width, h.toInt(), Bitmap.Config.ARGB_8888)
        val c = Canvas(bitmap)
        val top = h * design.stripFraction
        val bottom = h * design.bottomFraction
        val foil = mask(1.0, 1.0, 0.0); val chrome = mask(1.0, 0.35, 0.0); val body = mask(0.55, 0.08, 0.15); val ink = mask(0.1, 0.0, 0.5)
        val full = RectF(0f, 0f, w, h)
        if (asMask) {
            c.drawRect(full, Ink.fill(body))
        } else {
            c.drawRect(full, Ink.linear(0f, 0f, 0f, h, intArrayOf(Ink.rgb(0.93, 0.93, 0.93), Ink.rgb(0.86, 0.86, 0.86), Ink.rgb(0.9, 0.9, 0.9))))
            c.emblemPattern(design.emblem, full, w * 0.16f, Ink.color(design.topColor, 0.08))
        }
        // Bands.
        c.drawRect(RectF(0f, 0f, w, top), Ink.fill(if (asMask) foil else Ink.color(design.topColor)))
        run {
            val brand = Ink.textPaint(top * 0.2f, if (asMask) chrome else Color.WHITE, Weight.BLACK, Family.ROUNDED)
            val er = top * 0.3f * 0.5f
            val gap = w * 0.02f
            val bw = brand.width(design.brand)
            val x0 = (w - (er * 2 + gap + bw)) / 2
            val lineH = brand.fontMetrics.let { it.descent - it.ascent }
            val y0 = top / 2 - lineH / 2
            c.drawPath(Glyph.emblem(design.emblem, x0 + er, top / 2, er), Ink.fill(if (asMask) chrome else Ink.color(design.accent)))
            c.line(design.brand, x0 + er * 2 + gap, y0, brand)
        }
        c.drawRect(RectF(0f, h - bottom, w, h), Ink.fill(if (asMask) foil else Ink.color(design.bottomColor)))
        // The fine print.
        val textColor = if (asMask) ink else Ink.black(0.72)
        val left = w * 0.09f
        var y = top + h * 0.05f
        y += c.line("CONTAINS ${design.cardCount} CARDS", left, y, Ink.textPaint(w * 0.045f, textColor, Weight.HEAVY, Family.ROUNDED, tracking = w * 0.004f)) + h * 0.02f
        y += c.line(design.title.uppercase(), left, y, Ink.textPaint(w * 0.06f, textColor, Weight.BLACK, Family.ROUNDED)) + h * 0.02f
        y += fineLines(c, left, y, w * 0.82f, 9, 3, if (asMask) ink else Ink.black(0.35)) + h * 0.02f
        fineLines(c, left, y, w * 0.6f, 5, 7, if (asMask) ink else Ink.black(0.35))
        // Barcode and age mark along the bottom.
        val baseline = h - bottom - h * 0.04f
        c.drawPath(barcode(RectF(left, baseline - w * 0.14f, left + w * 0.42f, baseline), 44), Ink.fill(if (asMask) ink else Ink.black(0.85)))
        run {
            val paint = Ink.textPaint(w * 0.05f, textColor, Weight.BOLD, Family.ROUNDED)
            val tw = paint.width("6+")
            val fm = paint.fontMetrics
            val th = fm.descent - fm.ascent
            val pad = w * 0.02f
            val cx = w - left - (tw / 2 + pad)
            val cy = baseline - (th / 2 + pad)
            c.drawCircle(cx, cy, max(tw, th) / 2 + pad, Ink.stroke(if (asMask) ink else Ink.black(0.7), w * 0.006f))
            c.line("6+", cx, cy - th / 2, paint, Align.CENTER)
        }
        return bitmap
    }

    /** Rows of grey "text" of varying length. */
    private fun fineLines(c: Canvas, x: Float, y: Float, width: Float, lines: Int, seed: Int, color: Int): Float {
        val hgt = width * 0.018f
        val spacing = width * 0.025f
        val paint = Ink.fill(color)
        for (i in 0 until lines) {
            val f = 0.55 + 0.45 * abs(sin((i * 7 + seed) * 1.7))
            val yy = y + i * (hgt + spacing)
            c.drawRoundRect(RectF(x, yy, x + (width * f).toFloat(), yy + hgt), hgt / 2, hgt / 2, paint)
        }
        return lines * hgt + (lines - 1) * spacing
    }

    private fun barcode(rect: RectF, bars: Int): Path = Path().apply {
        val unit = rect.width() / (bars * 3)
        var x = rect.left
        for (i in 0 until bars) {
            val width = unit * (1 + (i * 7919 + 13) % 3)
            val gap = unit * (1 + (i * 104729 + 5) % 2)
            addRect(RectF(x, rect.top, x + width, rect.bottom), Path.Direction.CW)
            x += width + gap
            if (x > rect.right) break
        }
    }
}
