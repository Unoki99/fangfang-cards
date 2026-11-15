// Windows stand-ins for android.media (see AndroidContent.kt): the MOE recordings and 鬥拍字's voice are mp3 files,
// played here with Java Sound (and the mp3 decoder in the program).
package android.media

import com.unoki99.fangfang.desktop.Mp3
import java.io.File

class AudioAttributes private constructor() {
    class Builder {
        fun setUsage(u: Int) = this
        fun setContentType(c: Int) = this
        fun build() = AudioAttributes()
    }
    companion object {
        const val USAGE_MEDIA = 1
        const val CONTENT_TYPE_SPEECH = 1
        const val CONTENT_TYPE_MUSIC = 2
    }
}

/** plays one mp3 file (on a thread of its own) */
class MediaPlayer {
    fun interface OnCompletionListener { fun onCompletion(mp: MediaPlayer) }
    fun interface OnErrorListener { fun onError(mp: MediaPlayer, what: Int, extra: Int): Boolean }

    private var file: File? = null
    private var volume = 1f
    private var done: OnCompletionListener? = null
    private var failed: OnErrorListener? = null
    @Volatile private var play: Mp3.Playing? = null

    fun setAudioAttributes(a: AudioAttributes) {}
    fun setDataSource(path: String) { file = File(path) }
    fun setVolume(left: Float, right: Float) { volume = maxOf(left, right); play?.volume = volume }
    fun setOnCompletionListener(l: OnCompletionListener) { done = l }
    fun setOnErrorListener(l: OnErrorListener) { failed = l }
    fun prepare() { if (file?.isFile != true) throw java.io.IOException("no file") }
    fun start() {
        val f = file ?: return
        play = Mp3.play(f.inputStream(), volume, onEnd = { done?.onCompletion(this) }, onError = { failed?.onError(this, 1, 0) })
    }
    fun stop() { play?.stop() }
    fun release() { play?.stop(); play = null }
    val isPlaying: Boolean get() = play?.running == true
}
