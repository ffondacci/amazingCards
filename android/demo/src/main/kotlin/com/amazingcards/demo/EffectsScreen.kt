// Every shader pass of CardFX, with a live preview and a playground: the
// Android twin of EffectsCatalogView.
package com.amazingcards.demo

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.amazingcards.cardkit.core.Card
import com.amazingcards.cardkit.fx.CardEffect
import com.amazingcards.cardkit.fx.CardMotion
import com.amazingcards.cardkit.fx.CardMotionStage
import com.amazingcards.cardkit.stage.PackPrints
import com.amazingcards.cardkit.ui.EffectSurface
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val Background = Color(0xFF0F0F14)
private val Secondary = Color(0xFF9A9AA6)

@Composable
fun EffectsScreen(initialEffect: String? = null) {
    val context = LocalContext.current
    val prints = remember { PackPrints(context, provider = CustomArtworks.provider) }
    val subjects = remember { listOf(SampleLibrary.starryNight, SampleLibrary.vanGogh, SampleLibrary.andromeda, SampleLibrary.vincentCreature) }
    var faces by remember { mutableStateOf<Map<String, Bitmap>>(emptyMap()) }
    val showcase = CardEffect.showcase
    var selected by remember {
        mutableStateOf(initialEffect?.lowercase()?.let { wanted -> showcase.firstOrNull { it.displayName.lowercase() == wanted } ?: showcase.firstOrNull { it.displayName.lowercase().contains(wanted) } })
    }
    LaunchedEffect(Unit) {
        faces = withContext(Dispatchers.Default) { subjects.associate { it.id to prints.cardFace(it, 560) } }
    }
    val effect = selected
    if (effect != null) {
        BackHandler { selected = null }
        EffectPlayground(effect, subjects, faces) { selected = null }
        return
    }
    LazyColumn(Modifier.fillMaxSize().background(Background).statusBarsPadding()) {
        item { Text("Effects", fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color.White, modifier = Modifier.padding(16.dp)) }
        item { SectionHeader("Foil styles (holo)") }
        items(showcase.filter { it.isHolo }) { EffectRow(it, faces[SampleLibrary.starryNight.id]) { selected = it } }
        item { SectionHeader("Overlays and generators") }
        items(showcase.filter { !it.isHolo }) { EffectRow(it, faces[SampleLibrary.starryNight.id]) { selected = it } }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(title.uppercase(), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Secondary, modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp))
}

@Composable
private fun EffectRow(effect: CardEffect, picture: Bitmap?, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)
            .background(Color(0xFF1A1A22), RoundedCornerShape(12.dp)).clickable { onClick() }.padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Still preview, like `cardMotionIdle(animates: false)`.
        EffectSurface(if (effect.isGenerator) null else picture, listOf(effect), CardMotion.STILL, Modifier.width(54.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(effect.displayName, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            Spacer(Modifier.height(3.dp))
            Text(effect.summary, fontSize = 12.sp, color = Secondary, maxLines = 2)
        }
        if (effect.isTimeDriven) Icon(Icons.Default.Schedule, "Animated", tint = Secondary, modifier = Modifier.padding(start = 8.dp))
    }
}

/** Large interactive preview with an intensity slider (or a Play button) and a subject picker. */
@Composable
private fun EffectPlayground(effect: CardEffect, subjects: List<Card>, faces: Map<String, Bitmap>, onClose: () -> Unit) {
    var intensity by remember { mutableFloatStateOf(1f) }
    var subject by remember { mutableStateOf(subjects.first()) }
    val progress = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val animates = effect.isTimeDriven || effect.isAnimatable
    Column(Modifier.fillMaxSize().background(Background).statusBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.ArrowBack, "Back", tint = Color.White, modifier = Modifier.padding(8.dp).clickable { onClose() })
            Text(effect.displayName, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
            Spacer(Modifier.padding(20.dp))
        }
        Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 28.dp), contentAlignment = Alignment.Center) {
            CardMotionStage(Modifier.widthIn(max = 440.dp).fillMaxWidth(), animates = animates) { motion ->
                val applied = when (effect) {
                    is CardEffect.Sweep -> listOf(CardEffect.Sweep(progress = progress.value, intensity = 0.8f))
                    is CardEffect.Dissolve -> listOf(CardEffect.Dissolve(progress = if (progress.value > 0.5f) (1 - progress.value) * 2 else progress.value * 2))
                    else -> listOf(effect.scaled(intensity))
                }
                EffectSurface(if (effect.isGenerator) null else faces[subject.id], applied, motion, Modifier.fillMaxWidth())
            }
        }
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (effect.isAnimatable) {
                Button(onClick = { scope.launch { progress.snapTo(0f); progress.animateTo(1f, tween(1400, easing = FastOutSlowInEasing)) } }) {
                    Icon(Icons.Default.PlayArrow, null); Spacer(Modifier.width(6.dp)); Text("Play")
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Intensity", fontSize = 14.sp, color = Color.White)
                    Spacer(Modifier.width(12.dp))
                    Slider(value = intensity, onValueChange = { intensity = it }, valueRange = 0f..1f, modifier = Modifier.weight(1f))
                }
            }
            if (!effect.isGenerator) {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (card in subjects) FilterChip(selected = card.id == subject.id, onClick = { subject = card }, label = { Text(card.title, fontSize = 11.sp, maxLines = 1) })
                }
            }
            Text(effect.summary, fontSize = 12.sp, color = Secondary, textAlign = TextAlign.Center)
        }
    }
}
