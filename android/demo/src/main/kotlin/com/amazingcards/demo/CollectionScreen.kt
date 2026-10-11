// The sample collection: a grid of the twelve cards with their foil, and a
// full-size interactive card (drag to tilt, gyroscope, flip, finish picker),
// like the iOS CollectionView and CardDetailView.
package com.amazingcards.demo

import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.activity.compose.BackHandler
import com.amazingcards.cardkit.core.Card
import com.amazingcards.cardkit.core.CardFinish
import com.amazingcards.cardkit.fx.CardMotion
import com.amazingcards.cardkit.fx.CardMotionStage
import com.amazingcards.cardkit.fx.FinishRecipe
import com.amazingcards.cardkit.paint.CardFace
import com.amazingcards.cardkit.paint.CardMetrics
import com.amazingcards.cardkit.stage.PackPrints
import com.amazingcards.cardkit.ui.CardFaceView
import com.amazingcards.cardkit.ui.FlippableCard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun CollectionScreen(initialCardId: String? = null, dumpFaces: Boolean = false) {
    val context = LocalContext.current
    val prints = remember { PackPrints(context, provider = CustomArtworks.provider) }
    var faces by remember { mutableStateOf<Map<String, CardFace>>(emptyMap()) }
    var back by remember { mutableStateOf<Bitmap?>(null) }
    var selected by remember { mutableStateOf(SampleLibrary.all.firstOrNull { it.id == initialCardId }) }
    var showsFinish by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        val painted = withContext(Dispatchers.Default) { SampleLibrary.all.associate { it.id to prints.cardLayers(it, 560) } to prints.cardBack(560) }
        faces = painted.first; back = painted.second
        if (dumpFaces) withContext(Dispatchers.IO) {
            // `--es dumpFaces 1`: the painted layers as PNGs in files/faces, for QA (`adb pull`).
            val dir = java.io.File(context.filesDir, "faces").apply { mkdirs() }
            for ((id, face) in painted.first) {
                fun save(name: String, bitmap: Bitmap?) { bitmap ?: return; java.io.File(dir, "$id-$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) } }
                save("flat", face.flat); save("frame", face.frame); save("art", face.art); save("overlay", face.overlay)
            }
        }
    }
    val card = selected
    if (card != null && back != null) {
        BackHandler { selected = null }
        CardDetailScreen(card, faces[card.id], back!!, prints) { selected = null }
        return
    }
    Box(Modifier.fillMaxSize().background(Color(0xFF0F0F14))) {
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Collection", fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color.White)
                Spacer(Modifier.weight(1f))
                FilterChip(selected = showsFinish, onClick = { showsFinish = !showsFinish }, label = { Text("Foil in grid") })
            }
            LazyVerticalGrid(columns = GridCells.Adaptive(150.dp), contentPadding = PaddingValues(12.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                items(SampleLibrary.all) { card ->
                    val face = faces[card.id]
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { selected = card }) {
                        Box(Modifier.fillMaxWidth().aspectRatio(CardMetrics.ASPECT_RATIO).background(Color(0xFF1A1A22), RoundedCornerShape(8.dp))) {
                            // Still motion, like `cardMotionIdle(animates: false)`: the foil shows, nothing moves.
                            if (face != null) CardFaceView(card, face, CardMotion.STILL, showsFinish, Modifier.fillMaxSize())
                        }
                        Spacer(Modifier.height(8.dp))
                        Text("${card.rarity.displayName} · ${card.finish.displayName}", fontSize = 11.sp, color = Color(0xFF9A9AA6))
                    }
                }
            }
        }
    }
}

/** Full-size interactive card with finish picker, flip and gyroscope toggle. */
@Composable
private fun CardDetailScreen(card: Card, face: CardFace?, back: Bitmap, prints: PackPrints, onClose: () -> Unit) {
    var finish by remember { mutableStateOf(card.finish) }
    var isFaceUp by remember { mutableStateOf(true) }
    var usesGyro by remember { mutableStateOf(true) }
    var menu by remember { mutableStateOf(false) }
    val current = card.copy(finish = finish)
    val animates = FinishRecipe.recipe(finish, card.template).isTimeDriven
    Column(Modifier.fillMaxSize().background(Color(0xFF0F0F14)).statusBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.ArrowBack, "Back", tint = Color.White, modifier = Modifier.padding(8.dp).clickable { onClose() })
            Text(card.title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Spacer(Modifier.padding(20.dp))
        }
        Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 28.dp), contentAlignment = Alignment.Center) {
            if (face != null) {
                CardMotionStage(Modifier.widthIn(max = 440.dp).fillMaxWidth(), usesDeviceMotion = usesGyro, animates = animates, showcase = true) { motion ->
                    FlippableCard(current, face, back, isFaceUp, motion, Modifier.fillMaxWidth())
                }
            }
        }
        Column(Modifier.padding(bottom = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Box {
                OutlinedButton(onClick = { menu = true }) { Text("Finish: ${finish.displayName}") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    for (f in CardFinish.entries) DropdownMenuItem(text = { Text(f.displayName) }, onClick = { finish = f; menu = false })
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                OutlinedButton(onClick = { isFaceUp = !isFaceUp }) { Text("Flip") }
                FilterChip(selected = usesGyro, onClick = { usesGyro = !usesGyro }, label = { Text("Gyroscope") })
            }
            Text("Drag on the card to tilt it. ${card.template.name.lowercase().replaceFirstChar { it.uppercase() }} · ${card.rarity.displayName}", fontSize = 12.sp, color = Color(0xFF9A9AA6))
        }
    }
}
