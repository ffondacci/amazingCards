// Canvas helpers shared by the pack and card painters: scaled text,
// gradients, emblem glyphs and artwork loading.
package com.amazingcards.cardkit.paint

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import com.amazingcards.cardkit.core.CardArtwork
import com.amazingcards.cardkit.core.CardColor
import com.amazingcards.cardkit.core.PackEmblem
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Draws the `CardArtwork.Custom` pictures of an app at a given size. */
fun interface ArtworkProvider {
    fun draw(key: String, width: Int, height: Int): Bitmap?

    companion object { val NONE = ArtworkProvider { _, _, _ -> null } }
}

/** Decodes drawable assets once, downsampled, and asks the provider for custom pictures. */
class ArtworkResolver(private val context: Context, var provider: ArtworkProvider = ArtworkProvider.NONE) {
    private val cache = HashMap<String, Bitmap?>()

    fun bitmap(artwork: CardArtwork, width: Int, height: Int): Bitmap? = when (artwork) {
        is CardArtwork.Asset -> asset(artwork.name)
        is CardArtwork.Custom -> cache.getOrPut("custom:${artwork.key}:$width:$height") { provider.draw(artwork.key, width, height) }
        CardArtwork.None -> null
    }

    private fun asset(name: String): Bitmap? = cache.getOrPut("asset:$name") {
        val id = context.resources.getIdentifier(name, "drawable", context.packageName)
        if (id == 0) return@getOrPut null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeResource(context.resources, id, bounds)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1024) sample *= 2
        BitmapFactory.decodeResource(context.resources, id, BitmapFactory.Options().apply { inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888 })
    }

    fun clearCustom() { cache.keys.filter { it.startsWith("custom:") }.forEach { cache.remove(it) } }
}

enum class Weight { REGULAR, MEDIUM, SEMIBOLD, BOLD, HEAVY, BLACK }
enum class Family { DEFAULT, ROUNDED, SERIF, MONO }

internal object Ink {
    fun color(c: CardColor, alpha: Double = 1.0): Int = c.argb(alpha)
    fun white(alpha: Double) = Color.argb((alpha * 255).toInt(), 255, 255, 255)
    fun black(alpha: Double) = Color.argb((alpha * 255).toInt(), 0, 0, 0)
    fun rgb(r: Double, g: Double, b: Double, a: Double = 1.0) = Color.argb((a * 255).toInt(), (r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt())

    fun typeface(weight: Weight, family: Family, italic: Boolean = false): Typeface {
        val base = when (family) {
            Family.SERIF -> "serif"
            Family.MONO -> "monospace"
            Family.ROUNDED, Family.DEFAULT -> when (weight) {
                Weight.BLACK, Weight.HEAVY -> "sans-serif-black"
                Weight.MEDIUM, Weight.SEMIBOLD -> "sans-serif-medium"
                else -> "sans-serif"
            }
        }
        val style = when {
            family == Family.SERIF || family == Family.MONO -> if (weight >= Weight.SEMIBOLD) Typeface.BOLD else Typeface.NORMAL
            weight == Weight.BOLD -> Typeface.BOLD
            else -> Typeface.NORMAL
        } or (if (italic) Typeface.ITALIC else 0)
        return Typeface.create(base, style)
    }

    fun textPaint(size: Float, color: Int, weight: Weight = Weight.REGULAR, family: Family = Family.DEFAULT, italic: Boolean = false, tracking: Float = 0f): Paint =
        Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            textSize = size
            this.color = color
            typeface = typeface(weight, family, italic)
            if (tracking != 0f && size > 0) letterSpacing = tracking / size
        }

    fun fill(color: Int): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.FILL }
    fun stroke(color: Int, width: Float): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.STROKE; strokeWidth = width }

    fun linear(x0: Float, y0: Float, x1: Float, y1: Float, colors: IntArray, positions: FloatArray? = null): Paint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = LinearGradient(x0, y0, x1, y1, colors, positions, Shader.TileMode.CLAMP) }

    fun radial(cx: Float, cy: Float, r: Float, colors: IntArray, positions: FloatArray? = null): Paint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = RadialGradient(cx, cy, max(r, 1f), colors, positions, Shader.TileMode.CLAMP) }
}

/** Alignment of a line of text. */
enum class Align { LEFT, CENTER, RIGHT }

/** Width a paint needs for a string. */
internal fun Paint.width(text: String): Float = measureText(text)

/**
 * Draws one line, shrinking the font down to `minScale` to fit `maxWidth`
 * like SwiftUI's `minimumScaleFactor`. `y` is the top of the line box.
 * Returns the line height used.
 */
internal fun Canvas.line(text: String, x: Float, y: Float, paint: Paint, align: Align = Align.LEFT, maxWidth: Float = Float.MAX_VALUE, minScale: Float = 1f, shadow: Shadow? = null): Float {
    val original = paint.textSize
    var size = original
    if (maxWidth < Float.MAX_VALUE) {
        val w = paint.width(text)
        if (w > maxWidth) size = max(original * minScale, original * maxWidth / w)
    }
    paint.textSize = size
    val fm = paint.fontMetrics
    val baseline = y - fm.ascent
    val w = paint.width(text)
    val x0 = when (align) { Align.LEFT -> x; Align.CENTER -> x - w / 2; Align.RIGHT -> x - w }
    if (shadow != null) {
        val sp = Paint(paint).apply { color = shadow.color; maskFilter = if (shadow.radius > 0.5f) BlurMaskFilter(shadow.radius, BlurMaskFilter.Blur.NORMAL) else null; shader = null }
        drawText(text, x0 + shadow.dx, baseline + shadow.dy, sp)
    }
    drawText(text, x0, baseline, paint)
    val height = fm.descent - fm.ascent
    paint.textSize = original
    return height
}

/** Draws a paragraph wrapped on `maxWidth`, at most `maxLines`, shrinking to `minScale` so it fits. Returns the height used. */
internal fun Canvas.paragraph(text: String, x: Float, y: Float, paint: Paint, maxWidth: Float, maxLines: Int, minScale: Float = 1f, align: Align = Align.LEFT, lineSpacing: Float = 1.15f): Float {
    val original = paint.textSize
    var scale = 1f
    var lines: List<String>
    while (true) {
        paint.textSize = original * scale
        lines = wrap(text, paint, maxWidth)
        if (lines.size <= maxLines || scale <= minScale + 1e-3f) break
        scale = max(minScale, scale - 0.05f)
    }
    if (lines.size > maxLines) {
        lines = lines.take(maxLines).toMutableList().also { l ->
            var last = l.last()
            while (paint.width("$last…") > maxWidth && last.isNotEmpty()) last = last.dropLast(1)
            l[l.size - 1] = "$last…"
        }
    }
    val fm = paint.fontMetrics
    val lineHeight = (fm.descent - fm.ascent) * lineSpacing
    var yy = y
    for (l in lines) {
        val w = paint.width(l)
        val x0 = when (align) { Align.LEFT -> x; Align.CENTER -> x - w / 2; Align.RIGHT -> x - w }
        drawText(l, x0, yy - fm.ascent, paint)
        yy += lineHeight
    }
    paint.textSize = original
    return lineHeight * lines.size
}

private fun wrap(text: String, paint: Paint, maxWidth: Float): List<String> {
    val words = text.split(' ')
    val lines = ArrayList<String>()
    var current = StringBuilder()
    for (word in words) {
        val candidate = if (current.isEmpty()) word else "$current $word"
        if (paint.width(candidate) <= maxWidth || current.isEmpty()) {
            current = StringBuilder(candidate)
        } else {
            lines.add(current.toString())
            current = StringBuilder(word)
        }
    }
    if (current.isNotEmpty()) lines.add(current.toString())
    return lines
}

internal data class Shadow(val color: Int, val radius: Float, val dx: Float = 0f, val dy: Float = 0f)

/** Fills a path with a blurred drop shadow under it. */
internal fun Canvas.shadowed(path: Path, shadow: Shadow) {
    val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = shadow.color; maskFilter = BlurMaskFilter(max(shadow.radius, 0.5f), BlurMaskFilter.Blur.NORMAL) }
    save(); translate(shadow.dx, shadow.dy); drawPath(path, p); restore()
}

/** Draws a bitmap scaled to fill `rect`, centred, clipped. */
internal fun Canvas.drawCover(bitmap: Bitmap, rect: RectF, fit: Boolean = false) {
    val sx = rect.width() / bitmap.width
    val sy = rect.height() / bitmap.height
    val s = if (fit) min(sx, sy) else max(sx, sy)
    val w = bitmap.width * s
    val h = bitmap.height * s
    val m = Matrix()
    m.setScale(s, s)
    m.postTranslate(rect.left + (rect.width() - w) / 2, rect.top + (rect.height() - h) / 2)
    save()
    clipRect(rect)
    drawBitmap(bitmap, m, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
    restore()
}

/** Rounded rectangle path with a continuous-looking corner. */
internal fun roundedRect(rect: RectF, radius: Float): Path = Path().apply { addRoundRect(rect, radius, radius, Path.Direction.CW) }

/** Glyphs standing in for the SF Symbols of the emblems. */
internal object Glyph {
    /** Four-point sparkle centred at (cx, cy). */
    fun sparkle(cx: Float, cy: Float, r: Float): Path = Path().apply {
        val inner = r * 0.22f
        moveTo(cx, cy - r)
        for (i in 0 until 4) {
            val a = -PI / 2 + i * PI / 2
            val b = a + PI / 4
            lineTo(cx + (inner * cos(b)).toFloat(), cy + (inner * sin(b)).toFloat())
            val next = a + PI / 2
            lineTo(cx + (r * cos(next)).toFloat(), cy + (r * sin(next)).toFloat())
        }
        close()
        // A smaller companion star, like the symbol.
        val sx = cx + r * 0.75f; val sy = cy - r * 0.7f; val sr = r * 0.4f; val si = sr * 0.3f
        moveTo(sx, sy - sr)
        for (i in 0 until 4) {
            val a = -PI / 2 + i * PI / 2
            val b = a + PI / 4
            lineTo(sx + (si * cos(b)).toFloat(), sy + (si * sin(b)).toFloat())
            val next = a + PI / 2
            lineTo(sx + (sr * cos(next)).toFloat(), sy + (sr * sin(next)).toFloat())
        }
        close()
    }

    /** Painter's palette: a rounded blob with a thumb hole and four paint dots (drawn by the caller). */
    fun palette(cx: Float, cy: Float, r: Float): Path = Path().apply {
        addOval(RectF(cx - r, cy - r * 0.8f, cx + r, cy + r * 0.8f), Path.Direction.CW)
        addCircle(cx + r * 0.35f, cy + r * 0.25f, r * 0.22f, Path.Direction.CCW)
    }

    fun paletteDots(cx: Float, cy: Float, r: Float): List<Pair<Float, Float>> =
        listOf(cx - r * 0.5f to cy - r * 0.3f, cx - r * 0.15f to cy - r * 0.5f, cx + r * 0.25f to cy - r * 0.45f, cx - r * 0.55f to cy + r * 0.15f)

    /** Crescent moon with two small stars. */
    fun moonStars(cx: Float, cy: Float, r: Float): Path = Path().apply {
        val moon = Path().apply { addCircle(cx - r * 0.15f, cy + r * 0.1f, r * 0.72f, Path.Direction.CW) }
        val bite = Path().apply { addCircle(cx + r * 0.2f, cy - r * 0.1f, r * 0.62f, Path.Direction.CW) }
        moon.op(bite, Path.Op.DIFFERENCE)
        addPath(moon)
        addPath(star(cx + r * 0.55f, cy - r * 0.55f, r * 0.28f))
        addPath(star(cx + r * 0.2f, cy - r * 0.9f, r * 0.16f))
    }

    fun star(cx: Float, cy: Float, r: Float, points: Int = 5): Path = Path().apply {
        val inner = r * 0.45f
        for (i in 0 until points * 2) {
            val rr = if (i % 2 == 0) r else inner
            val a = -PI / 2 + i * PI / points
            val x = cx + (rr * cos(a)).toFloat(); val y = cy + (rr * sin(a)).toFloat()
            if (i == 0) moveTo(x, y) else lineTo(x, y)
        }
        close()
    }

    fun emblem(kind: PackEmblem, cx: Float, cy: Float, r: Float): Path = when (kind) {
        PackEmblem.SPARKLES -> sparkle(cx, cy, r)
        PackEmblem.PALETTE -> palette(cx, cy, r)
        PackEmblem.MOON_STARS -> moonStars(cx, cy, r)
    }

    /** Rarity glyphs: circle, diamond, star, sparkles, crown. */
    fun rarity(index: Int, cx: Float, cy: Float, r: Float): Path = when (index) {
        0 -> Path().apply { addCircle(cx, cy, r, Path.Direction.CW) }
        1 -> Path().apply { moveTo(cx, cy - r); lineTo(cx + r, cy); lineTo(cx, cy + r); lineTo(cx - r, cy); close() }
        2 -> star(cx, cy, r)
        3 -> sparkle(cx, cy, r)
        else -> Path().apply {
            moveTo(cx - r, cy + r * 0.7f); lineTo(cx - r, cy - r * 0.3f); lineTo(cx - r * 0.45f, cy + r * 0.1f); lineTo(cx, cy - r)
            lineTo(cx + r * 0.45f, cy + r * 0.1f); lineTo(cx + r, cy - r * 0.3f); lineTo(cx + r, cy + r * 0.7f); close()
        }
    }
}

/** Faint repeated emblem, like the ball pattern of real wrappers. */
internal fun Canvas.emblemPattern(kind: PackEmblem, rect: RectF, spacing: Float, color: Int) {
    val paint = Ink.fill(color)
    val columns = (rect.width() / spacing).toInt() + 2
    val rows = (rect.height() / spacing).toInt() + 2
    save(); clipRect(rect)
    for (row in 0 until rows) {
        for (column in 0 until columns) {
            val x = rect.left + column * spacing + (if (row % 2 == 0) 0f else spacing / 2) - spacing / 2
            val y = rect.top + row * spacing - spacing / 2
            drawPath(Glyph.emblem(kind, x, y, spacing * 0.225f), paint)
        }
    }
    restore()
}

internal fun Rect.toRectF() = RectF(this)
