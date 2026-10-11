package com.amazingcards.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.amazingcards.cardkit.stage.OpeningStyle

/** Tab root: the collection and the booster stage. `--es demoRoute booster` opens a tab at launch, `--es card <id>` a card. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val route = intent.getStringExtra("demoRoute") ?: "collection"
        val opening = intent.getStringExtra("opening")?.let { name -> OpeningStyle.entries.firstOrNull { it.name.equals(name, true) } } ?: OpeningStyle.TEAR
        val openAfter = intent.getStringExtra("openAfter")?.toLongOrNull() ?: 0L
        val cardId = intent.getStringExtra("card")
        val dumpFaces = intent.getStringExtra("dumpFaces") == "1"
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Color(0xFFFFD60A), surface = Color(0xFF0F0F14))) {
                var tab by remember { mutableIntStateOf(if (route == "booster") 1 else 0) }
                Scaffold(
                    containerColor = Color(0xFF0F0F14),
                    bottomBar = {
                        NavigationBar(containerColor = Color(0xFF15151C)) {
                            NavigationBarItem(selected = tab == 0, onClick = { tab = 0 }, icon = { Icon(Icons.Default.GridView, null) }, label = { Text("Collection") })
                            NavigationBarItem(selected = tab == 1, onClick = { tab = 1 }, icon = { Icon(Icons.Default.Inventory2, null) }, label = { Text("Booster") })
                        }
                    },
                ) { padding ->
                    Box(Modifier.fillMaxSize().padding(bottom = padding.calculateBottomPadding())) {
                        when (tab) {
                            0 -> CollectionScreen(cardId, dumpFaces)
                            else -> BoosterScreen(opening, openAfter)
                        }
                    }
                }
            }
        }
    }
}
