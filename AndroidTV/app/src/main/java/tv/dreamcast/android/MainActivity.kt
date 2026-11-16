package tv.dreamcast.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import kotlinx.coroutines.launch

private val background = Color(0xFF090E1A)
private val panel = Color(0xFF19263D)
private val focusedColor = Color(0xFF285CB6)
private val muted = Color(0xFFB9C6D8)

private enum class Tab(val title: String) {
    LIVE("Live TV"), SPORTS("SportsZone"), MOVIES("Movies"), SERIES("Series"), SETTINGS("Settings")
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { DreamCastApp() } }
    }
}

@Composable
private fun DreamCastApp() {
    val context = LocalContext.current
    val repository = remember { PlaylistRepository(context.applicationContext) }
    val scope = rememberCoroutineScope()
    val player = remember { ExoPlayer.Builder(context).build().apply { playWhenReady = true } }
    DisposableEffect(player) { onDispose { player.release() } }

    var tab by remember { mutableStateOf(Tab.LIVE) }
    var channels by remember { mutableStateOf<List<TvChannel>>(emptyList()) }
    var selectedGroup by remember { mutableStateOf("All") }
    var selectedChannel by remember { mutableStateOf<TvChannel?>(null) }
    var playingChannel by remember { mutableStateOf<TvChannel?>(null) }
    var fullScreen by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Add an M3U playlist from Settings to begin.") }
    var loading by remember { mutableStateOf(false) }
    var sourceUrl by remember { mutableStateOf(repository.savedUrl()) }

    fun play(channel: TvChannel) {
        if (playingChannel?.id != channel.id) {
            player.setMediaItem(MediaItem.fromUri(channel.streamUrl))
            player.prepare()
            player.play()
            playingChannel = channel
            repository.rememberChannel(channel.id)
        }
    }

    fun install(list: List<TvChannel>) {
        channels = list
        selectedGroup = "All"
        selectedChannel = list.firstOrNull { it.id == repository.lastChannelId() } ?: list.firstOrNull()
        status = "Loaded ${list.size} channels."
        tab = Tab.LIVE
    }

    LaunchedEffect(Unit) {
        loading = true
        try {
            install(repository.restore())
            if (channels.isEmpty()) status = "Add an M3U playlist from Settings to begin."
        } catch (e: Exception) {
            status = e.message ?: "Could not restore the playlist."
        } finally {
            loading = false
        }
    }

    val openFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            scope.launch {
                loading = true
                try {
                    install(repository.importFile(uri))
                    sourceUrl = ""
                } catch (e: Exception) {
                    status = e.message ?: "File import failed."
                } finally {
                    loading = false
                }
            }
        }
    }

    BackHandler(enabled = fullScreen || tab != Tab.LIVE) {
        if (fullScreen) fullScreen = false else tab = Tab.LIVE
    }

    if (fullScreen) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            VideoSurface(player, Modifier.fillMaxSize())
            TvButton(
                "Back to guide",
                active = false,
                modifier = Modifier.align(Alignment.TopStart).padding(20.dp)
            ) { fullScreen = false }
        }
        return
    }

    Column(
        Modifier.fillMaxSize().background(background).padding(horizontal = 32.dp, vertical = 20.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("DreamCAST TV 2", color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.width(30.dp))
            Tab.entries.forEach { item ->
                TvButton(item.title, active = tab == item, modifier = Modifier.padding(end = 8.dp)) {
                    tab = item
                }
            }
        }
        Spacer(Modifier.height(15.dp))
        when (tab) {
            Tab.LIVE -> {
                if (channels.isEmpty()) {
                    Column {
                        Text("Live TV", fontSize = 26.sp, color = Color.White)
                        Spacer(Modifier.height(16.dp))
                        Text(status, color = muted)
                        Spacer(Modifier.height(18.dp))
                        TvButton("Open playlist settings") { tab = Tab.SETTINGS }
                    }
                } else {
                    val groups = remember(channels) { listOf("All") + channels.map { it.group }.distinct().sorted() }
                    val displayed = remember(channels, selectedGroup) {
                        if (selectedGroup == "All") channels else channels.filter { it.group == selectedGroup }
                    }
                    Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        Column(Modifier.width(180.dp).fillMaxHeight().verticalScroll(rememberScrollState())) {
                            Text("Groups", color = muted, fontSize = 18.sp)
                            Spacer(Modifier.height(8.dp))
                            groups.forEach { group ->
                                TvButton(group, active = selectedGroup == group, modifier = Modifier.fillMaxWidth().padding(bottom = 6.dp)) {
                                    selectedGroup = group
                                }
                            }
                        }
                        Column(Modifier.weight(0.9f).fillMaxHeight()) {
                            Text("Channels (${displayed.size})", color = muted, fontSize = 18.sp)
                            Spacer(Modifier.height(8.dp))
                            LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                items(displayed, key = { it.id }) { channel ->
                                    TvButton(
                                        label = channel.name,
                                        active = selectedChannel?.id == channel.id,
                                        modifier = Modifier.fillMaxWidth()
                                    ) {
                                        if (selectedChannel?.id != channel.id) {
                                            selectedChannel = channel
                                        } else if (playingChannel?.id != channel.id) {
                                            play(channel)
                                        } else {
                                            fullScreen = true
                                        }
                                    }
                                }
                            }
                        }
                        Column(Modifier.weight(1.5f).fillMaxHeight()) {
                            Text(playingChannel?.name ?: "Preview", color = Color.White, fontSize = 22.sp)
                            Spacer(Modifier.height(8.dp))
                            Box(
                                Modifier.fillMaxWidth().weight(1f).background(Color.Black, RoundedCornerShape(10.dp))
                            ) {
                                if (playingChannel != null) VideoSurface(player, Modifier.fillMaxSize())
                                else Text("Select a channel, then press OK to play.", color = muted, modifier = Modifier.align(Alignment.Center))
                            }
                            Spacer(Modifier.height(12.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                TvButton("Play selected") { selectedChannel?.let(::play) }
                                TvButton("Full screen") {
                                    if (playingChannel != null) fullScreen = true
                                }
                            }
                            Spacer(Modifier.height(8.dp))
                            Text("EPG timeline is the next feature.", color = muted, fontSize = 15.sp)
                        }
                    }
                }
            }
            Tab.SETTINGS -> {
                Text("Playlist settings", fontSize = 26.sp, color = Color.White)
                Spacer(Modifier.height(12.dp))
                Text("M3U HTTP/HTTPS address", color = muted)
                Spacer(Modifier.height(8.dp))
                BasicTextField(
                    value = sourceUrl,
                    onValueChange = { sourceUrl = it },
                    singleLine = true,
                    textStyle = androidx.compose.ui.text.TextStyle(color = Color.White, fontSize = 20.sp),
                    modifier = Modifier.fillMaxWidth().background(panel, RoundedCornerShape(8.dp))
                        .padding(16.dp)
                )
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TvButton(if (loading) "Loading..." else "Import URL") {
                        if (!loading) scope.launch {
                            loading = true
                            try {
                                install(repository.importUrl(sourceUrl.trim()))
                            } catch (e: Exception) {
                                status = e.message ?: "Could not load playlist."
                            } finally {
                                loading = false
                            }
                        }
                    }
                    TvButton("Import local M3U") {
                        if (!loading) openFile.launch(arrayOf("*/*"))
                    }
                }
                Spacer(Modifier.height(15.dp))
                Text(status, color = muted)
                Spacer(Modifier.height(18.dp))
                Text("Only import playlists you have permission to access.", color = muted, fontSize = 15.sp)
            }
            Tab.SPORTS, Tab.MOVIES, Tab.SERIES -> {
                Text(tab.title, color = Color.White, fontSize = 28.sp)
                Spacer(Modifier.height(16.dp))
                Text("This section is being ported from DreamCAST TV for tvOS.", color = muted)
            }
        }
    }
}

@Composable
private fun VideoSurface(player: ExoPlayer, modifier: Modifier = Modifier) {
    AndroidView(
        factory = { context ->
            PlayerView(context).apply {
                useController = false
                this.player = player
                keepScreenOn = true
            }
        },
        update = { view -> view.player = player },
        modifier = modifier
    )
}

@Composable
private fun TvButton(
    label: String,
    active: Boolean = false,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val shade = if (focused) focusedColor else if (active) Color(0xFF24406E) else panel
    Text(
        text = label,
        color = Color.White,
        fontSize = 17.sp,
        maxLines = 1,
        fontWeight = if (focused || active) FontWeight.Bold else FontWeight.Normal,
        modifier = modifier
            .onFocusChanged { focused = it.isFocused }
            .background(shade, RoundedCornerShape(8.dp))
            .border(if (focused) 2.dp else 0.dp, if (focused) Color.White else Color.Transparent, RoundedCornerShape(8.dp))
            .clickable { onClick() }
            .padding(horizontal = 14.dp, vertical = 12.dp)
    )
}
