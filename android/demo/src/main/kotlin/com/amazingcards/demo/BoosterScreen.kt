// Pack-opening demo: the 3D studio of sealed packs; tap the front one to
// open it, tap through the cards, come back for another.
package com.amazingcards.demo

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.amazingcards.cardkit.core.BoosterGenerator
import com.amazingcards.cardkit.core.SeededRandom
import com.amazingcards.cardkit.stage.OpeningStyle
import com.amazingcards.cardkit.stage.PackPrints
import com.amazingcards.cardkit.stage.PackStageView
import com.amazingcards.cardkit.stage.StageLighting
import com.amazingcards.cardkit.stage.StagePhase
import com.amazingcards.cardkit.stage.StageSettings
import com.amazingcards.cardkit.stage.rememberStage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun BoosterScreen(initialOpening: OpeningStyle = OpeningStyle.TEAR, autoOpenAfterMs: Long = 0) {
    val context = LocalContext.current
    val designs = PackDesigns.all
    var night by remember { mutableStateOf(false) }
    var opening by remember { mutableStateOf(initialOpening) }
    var designIndex by remember { mutableIntStateOf(0) }
    var collected by remember { mutableIntStateOf(0) }
    var deals by remember { mutableIntStateOf(0) }
    var seed by remember { mutableStateOf(1uL) }
    val prints = remember { PackPrints(context, provider = CustomArtworks.provider) }
    val settings = StageSettings(lighting = if (night) StageLighting.NIGHT else StageLighting.STUDIO, opening = opening)
    val stage = rememberStage(settings)
    val design = designs[designIndex % designs.size]

    // The next pack and its pictures, prepared while the carousel idles.
    LaunchedEffect(deals) {
        val skins = withContext(Dispatchers.Default) {
            seed += 1uL
            val pack = BoosterGenerator.STANDARD.makePack(design.title, SampleLibrary.boosterPool, SeededRandom(seed))
            prints.cardSkins(pack.cards)
        }
        stage.prepareCards(skins)
    }
    LaunchedEffect(stage) {
        stage.onOpened = { index -> designIndex = index; collected += 5; deals += 1 }
        if (autoOpenAfterMs > 0) { kotlinx.coroutines.delay(autoOpenAfterMs); stage.open() }
    }

    Box(Modifier.fillMaxSize()) {
        PackStageView(stage, designs, prints, settings)
        val textColor = if (night) Color.White else Color(0.12f, 0.12f, 0.12f)
        val dimColor = if (night) Color.White.copy(alpha = 0.7f) else Color(0.35f, 0.35f, 0.35f)
        AnimatedVisibility(stage.phase == StagePhase.IDLE, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding()) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(top = 8.dp)) {
                Text(design.title.uppercase(), fontSize = 28.sp, fontWeight = FontWeight.Black, color = textColor, textAlign = TextAlign.Center)
                Spacer(Modifier.height(6.dp))
                Text("${design.cardCount} cards · tap the pack to open it", fontSize = 13.sp, color = dimColor)
                if (collected > 0) {
                    Spacer(Modifier.height(6.dp))
                    Text("$collected cards collected", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = dimColor)
                }
            }
        }
        AnimatedVisibility(stage.phase == StagePhase.IDLE, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.TopStart).statusBarsPadding().padding(12.dp)) {
            Box(
                Modifier.size(40.dp).background(if (night) Color(0xCC2A2A32) else Color(0xDDF2F2F5), CircleShape).clickable { night = !night },
                contentAlignment = Alignment.Center,
            ) {
                Icon(if (night) Icons.Default.LightMode else Icons.Default.DarkMode, contentDescription = "Lighting", tint = textColor)
            }
        }
        AnimatedVisibility(stage.phase == StagePhase.IDLE, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 12.dp)) {
            OpeningPicker(opening, night) { opening = it }
        }
    }
}

/** Horizontal pill of the opening styles, like the studio's. */
@Composable
private fun OpeningPicker(selection: OpeningStyle, night: Boolean, onSelect: (OpeningStyle) -> Unit) {
    Row(
        Modifier
            .background(if (night) Color(0xCC2A2A32) else Color(0xDDF2F2F5), RoundedCornerShape(50))
            .padding(4.dp)
            .horizontalScroll(rememberScrollState()),
    ) {
        for ((index, style) in OpeningStyle.entries.withIndex()) {
            val selected = style == selection
            Row(
                Modifier
                    .background(if (selected) (if (night) Color.White.copy(alpha = 0.18f) else Color.White) else Color.Transparent, RoundedCornerShape(50))
                    .clickable { onSelect(style) }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("${index + 1}", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = (if (night) Color.White else Color(0.35f, 0.35f, 0.35f)).copy(alpha = 0.6f))
                Spacer(Modifier.size(6.dp))
                Text(style.label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (night) Color.White else if (selected) Color(0.1f, 0.1f, 0.1f) else Color(0.35f, 0.35f, 0.35f))
            }
        }
    }
}
