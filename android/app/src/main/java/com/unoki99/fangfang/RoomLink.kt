package com.unoki99.fangfang

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

// MARK: - playing over the internet (一起玩, 詞龍): a room on the relay (../relay, on the user's own Cloudflare account)
//
// The same as the iPhone app's (Nearby.swift's relay): the room's name on the relay is a hash of the room code, and
// every message is encrypted with a key made from the code (AES-GCM, a new 12-byte nonce each: base64 of nonce +
// ciphertext + tag), so the relay passes on bytes it can't read. Each message is an envelope {"n": the sender's
// name, "h": 1 for "I'm here" (sent on arriving, and again when someone else arrives), "d": the game's own JSON}.

object RoomCrypto {
    private const val LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    private val rnd = SecureRandom()
    fun norm(code: String): String = code.uppercase().filter { it.isLetterOrDigit() }
    private fun sha256(s: String): ByteArray = MessageDigest.getInstance("SHA-256").digest(s.toByteArray(Charsets.UTF_8))
    /** the room's name on the relay (the code never leaves the app) */
    fun roomId(code: String): String = sha256("fangfang-room:" + norm(code)).joinToString("") { "%02x".format(it) }.take(32)
    fun key(code: String): ByteArray = sha256("fangfang-key:" + norm(code))
    /** a new room code: 8 letters and digits that can't be mixed up (XXXX-XXXX) */
    fun newCode(): String { val s = (0 until 8).map { LETTERS[rnd.nextInt(LETTERS.length)] }.joinToString(""); return s.take(4) + "-" + s.drop(4) }

    fun seal(key: ByteArray, plain: String): String {
        val nonce = ByteArray(12).also { rnd.nextBytes(it) }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        return Base64.getEncoder().encodeToString(nonce + c.doFinal(plain.toByteArray(Charsets.UTF_8)))
    }
    fun open(key: ByteArray, b64: String): String? = try {
        val all = Base64.getDecoder().decode(b64)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, all, 0, 12))
        String(c.doFinal(all, 12, all.size - 12), Charsets.UTF_8)
    } catch (_: Exception) { null }
}

/** the people in a room; a game's link is a subclass that reads its messages (received) and hears who came and went */
open class RoomLink(val myName: String) {
    /** the others, by their relay id → name */
    val players = mutableStateMapOf<String, String>()
    /** 0 not connected, 1 connecting, 2 in the room, 3 failed */
    var status by mutableStateOf(0)
    var error by mutableStateOf<String?>(null)
    var code by mutableStateOf("")
    private var ws: WebSocket? = null
    private var key: ByteArray? = null
    private val main = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    val everyone: Set<String> get() = (players.values + myName).toSet()

    /** into the room `code` on the relay at `server` (https://…workers.dev) */
    fun open(server: String, code: String) {
        close()
        val s = server.trim().trimEnd('/')
        if (s.isEmpty()) { status = 3; error = tr("還沒有連線伺服器：設定 → 卡片與練習 → 一起玩 → 連線伺服器。"); return }
        if (RoomCrypto.norm(code).length < 6) { status = 3; error = tr("房間代碼太短了。"); return }
        this.code = code
        key = RoomCrypto.key(code)
        val url = (if (s.startsWith("http://")) "ws://" + s.removePrefix("http://") else if (s.startsWith("https://")) "wss://" + s.removePrefix("https://")
            else if (s.startsWith("ws")) s else "wss://$s") + "/room/" + RoomCrypto.roomId(code)
        status = 1; error = null
        ws = client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) { main.launch { frame(text) } }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                main.launch {
                    if (ws !== webSocket) return@launch
                    status = 3; error = tr("連不上伺服器：") + (t.message ?: "")
                    for (n in players.values.toList()) left(n)
                    players.clear()
                }
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                main.launch { if (ws === webSocket) { status = 0; for (n in players.values.toList()) left(n); players.clear() } }
            }
        })
    }

    fun close() {
        ws?.close(1000, null); ws = null
        for (n in players.values.toList()) left(n)
        players.clear()
        status = 0
    }

    /** to everyone else in the room (the sender handles its own message itself) */
    fun sendPayload(d: String) = envelope(d, false)

    private fun envelope(d: String, hello: Boolean) {
        val k = key ?: return
        val w = ws ?: return
        val o = JSONObject().put("n", myName).put("h", if (hello) 1 else 0).put("d", d)
        w.send(RoomCrypto.seal(k, o.toString()))
    }

    private fun frame(text: String) {
        val o = try { JSONObject(text) } catch (_: Exception) { return }
        when (o.optString("sys")) {
            "welcome" -> { status = 2; envelope("", true) }
            "join" -> envelope("", true)
            "leave" -> { val id = o.optString("id"); players.remove(id)?.let { left(it) } }
            "msg" -> {
                val id = o.optString("from")
                val plain = RoomCrypto.open(key ?: return, o.optString("data")) ?: return
                val e = try { JSONObject(plain) } catch (_: Exception) { return }
                val name = e.optString("n")
                if (name.isEmpty()) return
                if (players[id] != name) { players[id] = name; joined(name) }
                if (e.optInt("h") == 1) return
                received(e.optString("d"))
            }
        }
    }

    open fun received(d: String) {}
    open fun joined(name: String) {}
    open fun left(name: String) {}

    companion object {
        val client: OkHttpClient by lazy { OkHttpClient.Builder().pingInterval(20, TimeUnit.SECONDS).build() }
    }
}
