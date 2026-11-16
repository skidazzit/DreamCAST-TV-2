package tv.dreamcast.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text

private val bg = Color(0xFF090E1A)
private val panel = Color(0xFF19263D)
private val selected = Color(0xFF285CB6)

private enum class Tab(val title: String) {
    LIVE("Live TV"), SPORTS("SportsZone"), MOVIES("Movies"), SERIES("Series"), SETTINGS("Settings")
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                DreamCastHome()
            }
        }
    }
}

@Composable
private fun DreamCastHome() {
    var current by remember { mutableStateOf(Tab.LIVE) }
    BackHandler(enabled = current != Tab.LIVE) { current = Tab.LIVE }
    Column(
        modifier = Modifier.fillMaxSize().background(bg).padding(horizontal = 48.dp, vertical = 32.dp)
    ) {
        Text("DreamCAST TV 2", fontSize = 32.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Spacer(Modifier.height(28.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Tab.entries.forEach { tab ->
                FocusTile(
                    label = tab.title,
                    isActive = current == tab,
                    onClick = { current = tab }
                )
            }
        }
        Spacer(Modifier.height(32.dp))
        Text(current.title, fontSize = 28.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        Spacer(Modifier.height(12.dp))
        Text(
            when (current) {
                Tab.LIVE -> "Channel groups, live guide, and mini-player will be added here."
                Tab.SPORTS -> "Fixtures, standings, and broadcaster matching will be added here."
                Tab.MOVIES -> "Movie categories, posters, and playback will be added here."
                Tab.SERIES -> "Series library and episodes will be added here."
                Tab.SETTINGS -> "Playlists, sports preferences, appearance, and local backup will be added here."
            },
            color = Color(0xFFBAC6D8),
            fontSize = 18.sp
        )
        Spacer(Modifier.height(28.dp))
        Text("Android TV foundation • Phase 1", color = Color(0xFF8A9AB3), fontSize = 15.sp)
    }
}

@Composable
private fun FocusTile(label: String, isActive: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val backgroundColor = when {
        focused -> selected
        isActive -> Color(0xFF24406E)
        else -> panel
    }
    Text(
        text = label,
        color = Color.White,
        fontSize = 18.sp,
        fontWeight = if (focused || isActive) FontWeight.Bold else FontWeight.Normal,
        modifier = Modifier
            .background(backgroundColor, RoundedCornerShape(10.dp))
            .onFocusChanged { focused = it.isFocused }
            .clickable(onClick = onClick)
            .padding(horizontal = 22.dp, vertical = 16.dp)
    )
}
