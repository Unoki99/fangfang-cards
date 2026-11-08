package com.unoki99.fangfang.widget

import com.unoki99.fangfang.tr
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

/** choosing a widget's 分類 (when it's added, and later by long-pressing it → 設定) */
class WidgetConfigActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        setResult(RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) { finish(); return }
        val cats = WidgetFiles.categories(this).ifEmpty { listOf(WidgetFiles.Category(-1, "常用詞", 0)) }
        setContent {
            var unknownOnly by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(WidgetFiles.unknownOnly(this, id)) }
            LazyColumn(Modifier.fillMaxSize().background(Color(0xFF1C1C1E)).statusBarsPadding().navigationBarsPadding(), contentPadding = PaddingValues(16.dp)) {
                item {
                    Text(tr("分類詞卡：選一個分類"), color = Color(0xFFF2F2F2), fontSize = 20.sp, modifier = Modifier.padding(bottom = 6.dp))
                    Text(tr("小工具會顯示這個分類的詞（「熟悉」的詞不會出現），每個鐘頭換一個。") +
                        if (WidgetFiles.categories(this@WidgetConfigActivity).isEmpty()) tr("\n先打開方方詞卡一次，分類才會出現。") else "",
                        color = Color(0xFFA3A3A8), fontSize = 13.sp, modifier = Modifier.padding(bottom = 12.dp))
                    Row(Modifier.fillMaxWidth().background(Color(0xFF2B2B2D)).clickable { unknownOnly = !unknownOnly; WidgetFiles.setUnknownOnly(this@WidgetConfigActivity, id, unknownOnly) }
                        .padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        Text(tr("只顯示不熟的詞"), color = Color(0xFFF2F2F2), fontSize = 17.sp, modifier = Modifier.weight(1f))
                        androidx.compose.material3.Switch(unknownOnly, { unknownOnly = it; WidgetFiles.setUnknownOnly(this@WidgetConfigActivity, id, it) })
                    }
                    Text(tr("打開的話只出現你往左滑過的詞。也可以選「不熟的詞（台語）」「不熟的詞（華語）」或華語的等級。"),
                        color = Color(0xFFA3A3A8), fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp, bottom = 12.dp))
                }
                items(cats) { c ->
                    Row(Modifier.fillMaxWidth().background(Color(0xFF2B2B2D)).clickable { choose(id, c.i) }.padding(16.dp)) {
                        Text(c.n, color = Color(0xFFF2F2F2), fontSize = 17.sp, modifier = Modifier.weight(1f))
                        if (c.c > 0) Text(tr("{0} 個詞", c.c), color = Color(0xFFA3A3A8), fontSize = 13.sp)
                    }
                    Spacer(Modifier.height(1.dp))
                }
            }
        }
    }

    private fun choose(id: Int, cat: Int) {
        WidgetFiles.setCategory(this, id, cat)
        lifecycleScope.launch {
            try {
                val gid = GlanceAppWidgetManager(this@WidgetConfigActivity).getGlanceIdBy(id)
                WordWidget().update(this@WidgetConfigActivity, gid)
            } catch (_: Exception) {}
            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
            finish()
        }
    }
}
