// (Windows stand-ins, see ActivityCompose.kt)
package androidx.activity.result.contract

import android.net.Uri
import com.unoki99.fangfang.desktop.FilePick

abstract class ActivityResultContract<I, O> {
    abstract fun pick(input: I): O
}

object ActivityResultContracts {
    /** 另存: a file name to start with → the file chosen (null: cancelled) */
    class CreateDocument(private val mimeType: String) : ActivityResultContract<String, Uri?>() {
        override fun pick(input: String): Uri? = FilePick.save(input)?.let { Uri.fromFile(it) }
    }
    /** 開啟 → the file chosen */
    class OpenDocument : ActivityResultContract<Array<String>, Uri?>() {
        override fun pick(input: Array<String>): Uri? = FilePick.open()?.let { Uri.fromFile(it) }
    }
    /** a folder (the backup folder) */
    class OpenDocumentTree : ActivityResultContract<Uri?, Uri?>() {
        override fun pick(input: Uri?): Uri? = FilePick.folder()?.let { Uri.fromFile(it) }
    }
    /** (Android's permissions: nothing to ask on Windows) */
    class RequestPermission : ActivityResultContract<String, Boolean>() {
        override fun pick(input: String): Boolean = true
    }
}
