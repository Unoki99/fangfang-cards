// (Windows stand-in, see AndroidContent.kt)
package android.net

import java.io.File
import java.net.URI
import java.net.URLDecoder

/** an address: a file picked on this computer (file:…), or a link (fangfangcards://…) */
class Uri private constructor(private val s: String) {
    private val u: URI? = try { URI(s) } catch (_: Exception) { null }
    val scheme: String? get() = u?.scheme ?: s.substringBefore(":", "").ifEmpty { null }
    val host: String? get() = u?.host ?: s.substringAfter("://", "").substringBefore("/").substringBefore("?").ifEmpty { null }
    val path: String? get() = u?.path
    val lastPathSegment: String? get() = path?.trimEnd('/')?.substringAfterLast('/')
    fun getQueryParameter(key: String): String? {
        val q = s.substringAfter("?", "").substringBefore("#")
        for (part in q.split("&")) {
            val k = part.substringBefore("=")
            if (k == key) return try { URLDecoder.decode(part.substringAfter("=", ""), "UTF-8") } catch (_: Exception) { part.substringAfter("=", "") }
        }
        return null
    }
    /** the file it names (file: addresses), or null */
    fun toFile(): File? = try { if (scheme == "file") File(URI(s)) else if (scheme == null) File(s) else null } catch (_: Exception) { null }
    override fun toString() = s
    override fun equals(other: Any?) = other is Uri && other.s == s
    override fun hashCode() = s.hashCode()

    companion object {
        @JvmStatic fun parse(s: String): Uri = Uri(s)
        @JvmStatic fun fromFile(f: File): Uri = Uri(f.toURI().toString())
    }
}
