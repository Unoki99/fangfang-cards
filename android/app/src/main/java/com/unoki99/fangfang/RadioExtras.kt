package com.unoki99.fangfang

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Calendar

// 電台's extras, the same as the iPhone / iPad's (shared by Android and the Windows / Mac program): the minutes
// listened (我的進度), what the station sends (電台送來的資料), 電台鬧鐘 (a station at a time each morning, while the
// program is open), and 我的歌 (songs heard on the radio, kept to find again).

object RadioExtras {
    private val scope = MainScope()
    private var started = false
    /** 電台送來的資料: what the station playing has sent (newest first: when, the text) */
    val metaLog = mutableStateListOf<Pair<Long, String>>()

    /** (called once the radio is set up) */
    fun start() {
        if (started) return
        started = true
        // 我的進度: a minute at a time while a station plays
        scope.launch {
            while (true) {
                delay(60_000)
                if (Radio.state == Radio.State.PLAYING && Store.loaded) Store.addListening(1.0, 0)
            }
        }
        // 電台送來的資料: a new station starts a new list; each new text the station sends goes on top
        scope.launch { snapshotFlow { Radio.current?.id }.collect { metaLog.clear() } }
        scope.launch {
            snapshotFlow { Radio.nowPlaying }.collect { t ->
                if (t.isNullOrBlank() || metaLog.firstOrNull()?.second == t) return@collect
                metaLog.add(0, System.currentTimeMillis() to t)
                while (metaLog.size > 30) metaLog.removeAt(metaLog.size - 1)
            }
        }
        // 電台鬧鐘: looked at every 15 seconds
        scope.launch {
            var rang = 0L
            while (true) {
                delay(15_000)
                if (!Prefs.radioAlarmOn.value) continue
                val c = Calendar.getInstance()
                val now = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
                if (now == Prefs.radioAlarmTime.value && System.currentTimeMillis() - rang > 120_000) {
                    rang = System.currentTimeMillis()
                    ring()
                }
            }
        }
    }

    /** the alarm's station (the one chosen, or the first) */
    fun alarmStation(): RadioStation? = Radio.stations.firstOrNull { it.id == Prefs.radioAlarmStation.value } ?: Radio.stations.firstOrNull()

    private fun ring() {
        val st = alarmStation() ?: return
        if (Radio.state != Radio.State.PLAYING) Radio.play(st)
    }

    /** "07:00" */
    fun alarmText(): String { val m = Prefs.radioAlarmTime.value; return "%02d:%02d".format(m / 60, m % 60) }
}

/** a song kept in 我的歌 */
data class SavedSong(val id: String, val title: String, val artist: String, val station: String?, val lang: Int, val date: Long) {
    /** "周杰倫 晴天": to search with */
    val query: String get() = listOf(artist, title).filter { it.isNotEmpty() }.joinToString(" ")
    fun toMap(): Map<String, Any?> = mapOf("id" to id, "title" to title, "artist" to artist, "station" to station, "lang" to lang, "date" to date)
}

/** 我的歌: songs heard on the radio, newest first */
object SongList {
    var version by mutableIntStateOf(0); private set
    private var list: MutableList<SavedSong>? = null

    @Suppress("UNCHECKED_CAST")
    val songs: List<SavedSong> get() {
        list?.let { return it }
        val l = try {
            ((JReader(Prefs.savedSongs.value.ifEmpty { "[]" }).any() as? List<Any?>) ?: emptyList()).mapNotNull { o ->
                val m = o as? Map<String, Any?> ?: return@mapNotNull null
                SavedSong(m["id"] as? String ?: return@mapNotNull null, m["title"] as? String ?: "", m["artist"] as? String ?: "",
                    m["station"] as? String, (m["lang"] as? Number)?.toInt() ?: 0, (m["date"] as? Number)?.toLong() ?: 0L)
            }.toMutableList()
        } catch (_: Exception) { ArrayList() }
        list = l
        return l
    }
    private fun save() { Prefs.savedSongs.value = JWriter.any(songs.map { it.toMap() }); version++ }

    /** the song playing now: what the station says ("Artist - Title") */
    fun current(): Pair<String, String>? {
        val p = Radio.nowPlaying?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        for (sep in listOf(" - ", " – ", " — ", " / ")) {
            val i = p.indexOf(sep)
            if (i > 0) {
                val a = p.substring(0, i).trim(); val t = p.substring(i + sep.length).trim()
                if (a.isNotEmpty() && t.isNotEmpty()) return t to a
            }
        }
        return p to ""
    }

    fun has(title: String, artist: String) = songs.any { it.title.equals(title, true) && it.artist.equals(artist, true) }

    /** the song playing now in the list, or out of it again */
    fun toggle() {
        val (t, a) = current() ?: return
        val l = songs as MutableList<SavedSong>
        if (has(t, a)) l.removeAll { it.title.equals(t, true) && it.artist.equals(a, true) }
        else l.add(0, SavedSong(java.util.UUID.randomUUID().toString(), t, a, Radio.current?.name, Radio.current?.lang ?: Store.lang, System.currentTimeMillis()))
        save()
    }
    fun remove(s: SavedSong) { (songs as MutableList<SavedSong>).removeAll { it.id == s.id }; save() }
}
