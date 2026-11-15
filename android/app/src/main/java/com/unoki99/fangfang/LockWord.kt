package com.unoki99.fangfang

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.unoki99.fangfang.engine.*

// 鎖定畫面的詞 (Android's version of the iPhone's Dynamic Island): leaving the app puts one of your 練習範圍's words
// in a quiet notification (on the lock screen too): the word and its reading; pulled open, its meaning and 下一個.
// Tapping it opens the word's entry in the app. Coming back to the app takes it away.
// The words are written out when the app is left, so 下一個 works without the app running.

object LockWord {
    private const val CHANNEL = "lockword"
    private const val ID = 4201
    private const val POOL = "lockPool"
    private const val AT = "lockAt"
    const val NEXT = "com.unoki99.fangfang.LOCK_NEXT"
    private fun prefs(c: Context) = c.getSharedPreferences("fangfang", Context.MODE_PRIVATE)

    /** 設定: on / off; which words ("" the 練習範圍, "unknown" all of 不熟) */
    val on: Boolean get() = Prefs.lockWord.value
    val source: String get() = Prefs.lockSource.value

    private fun cards(): List<Card> {
        val p = Store.practiceCards
        return if (source == "unknown" || p.isEmpty()) Store.unknownCards else p
    }

    /** leaving the app: a handful of words, ready written, and the first one shown */
    fun start(c: Context) {
        if (!on || !Store.loaded) return
        if (Build.VERSION.SDK_INT >= 33 && c.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) return
        val rom = Prefs.rom.value; val place = Prefs.place.value
        val pool = cards().shuffled().take(60).map { card ->
            val m = try { Store.practiceMeaning(card).second } catch (_: Exception) { "" }
            listOf(card.k, Store.cardHan(card, place, 0).plain(), Store.cardRom(card, rom, place).plain(), m, Lang.kind(card.k).toString())
        }
        if (pool.isEmpty()) return
        prefs(c).edit().putString(POOL, JWriter.any(pool)).putInt(AT, 0).apply()
        show(c, 0)
    }

    /** back in the app: taken away */
    fun end(c: Context) { NotificationManagerCompat.from(c).cancel(ID) }

    @Suppress("UNCHECKED_CAST")
    private fun pool(c: Context): List<List<String>> {
        val s = prefs(c).getString(POOL, "") ?: ""
        if (s.isEmpty()) return emptyList()
        return try { (JReader(s).any() as? List<Any?>)?.mapNotNull { (it as? List<Any?>)?.map { x -> x as? String ?: "" } } ?: emptyList() }
        catch (_: Exception) { emptyList() }
    }

    /** 下一個 */
    fun next(c: Context) {
        val n = pool(c).size
        if (n == 0) return
        val at = (prefs(c).getInt(AT, 0) + 1) % n
        prefs(c).edit().putInt(AT, at).apply()
        show(c, at)
    }

    private fun show(c: Context, at: Int) {
        val w = pool(c).getOrNull(at) ?: return
        val nm = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, tr("鎖定畫面的詞"), NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false); lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            })
        }
        val key = w[0]; val word = w[1]; val reading = w[2]; val meaning = w[3]; val lang = w.getOrNull(4) ?: "0"
        // (tapping it: the word's entry in the app)
        val open = PendingIntent.getActivity(c, 1,
            Intent(Intent.ACTION_VIEW, Uri.parse("fangfangcards://dict?lang=$lang&word=" + Uri.encode(key)), c, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val next = PendingIntent.getBroadcast(c, 2, Intent(NEXT).setClass(c, LockWordReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_notify)
            .setContentTitle(word)
            .setContentText(reading)
            .setStyle(NotificationCompat.BigTextStyle().bigText(if (meaning.isEmpty()) reading else "$reading\n$meaning"))
            .setOngoing(true).setOnlyAlertOnce(true).setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(open)
            .addAction(0, tr("下一個"), next)
            .build()
        try { NotificationManagerCompat.from(c).notify(ID, n) } catch (_: SecurityException) {}
    }
}

class LockWordReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        // (the app may not be running: its settings read first)
        Prefs.init(c.applicationContext)
        if (i.action == LockWord.NEXT) LockWord.next(c)
    }
}
