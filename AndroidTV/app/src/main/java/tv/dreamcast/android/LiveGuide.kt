package tv.dreamcast.android

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private const val SLOT_MILLIS = 30 * 60 * 1000L
private val dark = Color(0xFF111B2E)
private val missing = Color(0xFF202B41)

@Composable
fun LiveGuide(
    channels: List<TvChannel>,
    programmes: List<EpgProgramme>,
    selectedChannel: TvChannel?,
    selectedGroup: String,
    onGroupSelected: (String) -> Unit,
    onChannelPressed: (TvChannel) -> Unit,
    modifier: Modifier = Modifier
) {
    // Timeline follows current time, not focus movement. The column of programme data has no focus targets.
    val now = System.currentTimeMillis()
    val timeBase = now - now % SLOT_MILLIS
    val groups = remember(channels) { listOf("All") + channels.map { it.group }.distinct().sorted() }
    val shown = remember(channels, selectedGroup) {
        if (selectedGroup == "All") channels else channels.filter { it.group == selectedGroup }
    }
    val byId = remember(programmes) { programmes.groupBy { it.channelId.lowercase(Locale.ROOT) } }
    val formatter = remember { SimpleDateFormat("h:mm a", Locale.getDefault()) }
    val timeColumns = 4

    Row(modifier, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.width(170.dp).fillMaxHeight().verticalScroll(rememberScrollState())) {
            Text("Groups", color = Color.LightGray, fontSize = 16.sp)
            Spacer(Modifier.height(10.dp))
            groups.forEach { group ->
                GuideButton(group, selectedGroup == group, Modifier.fillMaxWidth().padding(bottom = 5.dp)) {
                    onGroupSelected(group)
                }
            }
        }

        Column(Modifier.weight(1f)) {
            Row(Modifier.fillMaxWidth().background(dark, RoundedCornerShape(7.dp))) {
                Box(Modifier.width(250.dp).height(40.dp).padding(10.dp)) {
                    Text("CHANNELS", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                }
                for (slot in 0 until timeColumns) {
                    Text(
                        formatter.format(Date(timeBase + slot * SLOT_MILLIS)),
                        modifier = Modifier.weight(1f).padding(vertical = 10.dp, horizontal = 5.dp),
                        color = Color.White, fontSize = 14.sp
                    )
                }
            }
            Spacer(Modifier.height(5.dp))
            LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                items(shown, key = { it.id }) { channel ->
                    val events = byId[channel.epgId.lowercase(Locale.ROOT)].orEmpty()
                    Row(Modifier.fillMaxWidth().height(64.dp), verticalAlignment = Alignment.CenterVertically) {
                        // The only focusable target in each guide row is the channel name.
                        GuideButton(
                            channel.name,
                            selectedChannel?.id == channel.id,
                            Modifier.width(250.dp).height(60.dp)
                        ) { onChannelPressed(channel) }
                        repeat(timeColumns) { index ->
                            val start = timeBase + index * SLOT_MILLIS
                            val end = start + SLOT_MILLIS
                            val event = events.firstOrNull { it.startMillis < end && it.endMillis > start }
                            Box(
                                Modifier.weight(1f).height(60.dp)
                                    .padding(start = 3.dp)
                                    .background(missing, RoundedCornerShape(5.dp))
                                    .padding(8.dp)
                            ) {
                                Text(
                                    event?.title ?: "No data",
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                    color = if (event == null) Color.Gray else Color.White,
                                    fontSize = 13.sp,
                                    lineHeight = 17.sp
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
