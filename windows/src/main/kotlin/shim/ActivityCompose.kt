// Windows stand-ins for androidx.activity (see AndroidContent.kt): Android's back gesture is Esc here (and the mouse's
// back button), and the file pickers are Windows' own Save and Open dialogs.
package androidx.activity.compose

import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.runtime.*
import com.unoki99.fangfang.desktop.Back

/** what Esc (or the mouse's back button) does while this is on screen: the last one shown first, as on Android */
@Composable
fun BackHandler(enabled: Boolean = true, onBack: () -> Unit) {
    val on = rememberUpdatedState(enabled)
    val run = rememberUpdatedState(onBack)
    DisposableEffect(Unit) {
        val h = Back.Handler({ on.value }, { run.value() })
        Back.add(h)
        onDispose { Back.remove(h) }
    }
}

class ManagedActivityResultLauncher<I, O>(private val contract: State<ActivityResultContract<I, O>>, private val result: State<(O) -> Unit>) {
    fun launch(input: I) {
        val r = contract.value.pick(input)
        result.value(r)
    }
}

@Composable
fun <I, O> rememberLauncherForActivityResult(contract: ActivityResultContract<I, O>, onResult: (O) -> Unit): ManagedActivityResultLauncher<I, O> {
    val c = rememberUpdatedState(contract)
    val r = rememberUpdatedState(onResult)
    return remember { ManagedActivityResultLauncher(c, r) }
}
