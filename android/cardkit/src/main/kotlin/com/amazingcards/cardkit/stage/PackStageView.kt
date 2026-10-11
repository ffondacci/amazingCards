// The 3D carousel of sealed packs as a composable: prints the designs on
// the pouches, shows the hint pill and the close button, and hands the
// tap to the host through `onOpened`.
package com.amazingcards.cardkit.stage

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape
import com.amazingcards.cardkit.core.PackDesign

/** Creates a stage bound to the composition. */
@Composable
fun rememberStage(settings: StageSettings = StageSettings.STANDARD): Stage {
    val context = LocalContext.current
    val stage = remember { Stage(context, settings) }
    DisposableEffect(stage) { onDispose { stage.destroy() } }
    return stage
}

@Composable
fun PackStageView(
    stage: Stage,
    designs: List<PackDesign>,
    prints: PackPrints,
    settings: StageSettings,
    modifier: Modifier = Modifier,
) {
    val night = settings.lighting == StageLighting.NIGHT
    LaunchedEffect(settings, designs.size) {
        stage.settings = settings.copy(packs = maxOf(settings.packs, designs.size))
    }
    LaunchedEffect(designs, prints) {
        if (designs.isEmpty()) return@LaunchedEffect
        val packs = maxOf(settings.packs, designs.size)
        for (index in 0 until packs) stage.setSkin(index, prints.skin(designs[index % designs.size]))
    }
    Box(modifier.fillMaxSize()) {
        StageView(stage, Modifier.fillMaxSize())
        AnimatedVisibility(visible = stage.hint != null, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp)) {
            Text(
                stage.hint ?: "",
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = if (night) Color.White else Color(0.15f, 0.15f, 0.15f),
                modifier = Modifier
                    .background(if (night) Color(0xCC2A2A32) else Color(0xDDF2F2F5), RoundedCornerShape(50))
                    .padding(horizontal = 16.dp, vertical = 9.dp),
            )
        }
        AnimatedVisibility(visible = stage.phase != StagePhase.IDLE, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.TopEnd).padding(16.dp)) {
            Box(
                Modifier
                    .size(40.dp)
                    .background(if (night) Color(0xCC2A2A32) else Color(0xDDF2F2F5), CircleShape)
                    .clickable { stage.exit() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Default.Close, contentDescription = "Close", tint = if (night) Color.White else Color(0.15f, 0.15f, 0.15f))
            }
        }
    }
}
