// (Windows stand-ins, see AndroidContent.kt)
package android.content.res

import java.io.File
import java.io.FileNotFoundException
import java.io.InputStream

/** "assets": the dictionaries made on this computer (%LOCALAPPDATA%\FangfangCards\data), else the program's own files
 *  (ui_en.json, the converters in install/) */
class AssetManager(private val dataDir: File, private val more: List<File> = emptyList()) {
    fun open(name: String): InputStream {
        val f = File(dataDir, name)
        if (f.isFile) return f.inputStream()
        // (a Mac: the dictionaries the iPad app's install.sh made, when this program's own aren't there)
        for (d in more) { val g = File(d, name); if (g.isFile) return g.inputStream() }
        return AssetManager::class.java.getResourceAsStream("/$name") ?: throw FileNotFoundException(name)
    }
    fun list(path: String): Array<String> = (File(dataDir, path).list() ?: emptyArray())
}
