// Renders the printed sides of pack designs and the pictures of cards for
// the 3D stage, cached by design and card.
package com.amazingcards.cardkit.stage

import android.content.Context
import android.graphics.Bitmap
import com.amazingcards.cardkit.core.Card
import com.amazingcards.cardkit.core.PackDesign
import com.amazingcards.cardkit.paint.ArtworkProvider
import com.amazingcards.cardkit.paint.ArtworkResolver
import com.amazingcards.cardkit.paint.CardPainter
import com.amazingcards.cardkit.paint.PackPainter

class PackPrints(context: Context, var width: Int = 1024, provider: ArtworkProvider = ArtworkProvider.NONE) {
    private val resolver = ArtworkResolver(context, provider)
    private val packs = PackPainter(resolver)
    private val cards = CardPainter(resolver, context)
    private val cache = HashMap<PackDesign, PackSkin>()
    private var backCache: Bitmap? = null

    var artworkProvider: ArtworkProvider
        get() = resolver.provider
        set(value) { resolver.provider = value; resolver.clearCustom(); cache.clear() }

    /** The skin of a design, rendered on first use. */
    fun skin(design: PackDesign): PackSkin = cache.getOrPut(design) {
        PackSkin(
            id = design.hashCode().toString(),
            front = packs.front(design, width, asMask = false),
            back = packs.back(design, width, asMask = false),
            frontMask = packs.front(design, width / 2, asMask = true),
            backMask = packs.back(design, width / 2, asMask = true),
        )
    }

    /** Pictures of the cards of one pack, front and back, with a foil mask for the foil finishes. */
    fun cardSkins(cards: List<Card>, width: Int = 640): List<CardSkin> {
        val back = backCache ?: this.cards.back(width).also { backCache = it }
        return cards.map { card ->
            val mask = if (card.isFoil) Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.rgb(153, 204, 0)) } else null
            CardSkin("${card.id}-$width", this.cards.front(card, width), back, mask)
        }
    }

    /** One card face, flattened. */
    fun cardFace(card: Card, width: Int): Bitmap = cards.front(card, width)
    /** One card face in layers, for the interactive card. */
    fun cardLayers(card: Card, width: Int): com.amazingcards.cardkit.paint.CardFace = cards.face(card, width)
    fun cardBack(width: Int): Bitmap = cards.back(width)
}
