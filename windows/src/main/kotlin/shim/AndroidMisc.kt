// (Windows stand-ins, see AndroidContent.kt)
package android.content.res

import java.io.File
import java.io.FileNotFoundException
import java.io.InputStream

/** "assets": the dictionaries made on this computer (%LOCALAPPDATA%\FangfangCards\data), else the program's own files
 *  (ui_en.json, the converters in install/) */
class AssetManager(private val dataDir: File) {
    fun open(name: String): InputStream {
        val f = File(dataDir, name)
        if (f.isFile) return f.inputStream()
        return AssetManager::class.java.getResourceAsStream("/$name") ?: throw FileNotFoundException(name)
    }
    fun list(path: String): Array<String> = (File(dataDir, path).list() ?: emptyArray())
}
