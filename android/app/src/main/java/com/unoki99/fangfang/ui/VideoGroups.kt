package com.unoki99.fangfang.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.Lang
import com.unoki99.fangfang.tr

// 影片詞組: the words chosen from one video / episode with the browser add-on's subtitle panel, kept together as a
// group named after the video (made on the iPhone, they come over in its backup file). Your own scopes (自己的範圍)
// put several groups together, e.g. every episode of one show (創作範圍: a name, then tick its groups).
// The same as the iPhone app's.

private fun dateText(t: Double): String =
    java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date((t * 1000).toLong()))

@Composable
fun VideoGroupsPage(onBack: () -> Unit) {
    Store.rev
    val nav = LocalNav.current
    val groups = Store.groupIds
    var renaming by remember { mutableStateOf<String?>(null) }
    var deleting by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("影片詞組"), onBack, settings = false) {
            if (groups.isNotEmpty()) TextButton(onClick = { nav.push(Route.ScopeEditor(null)) }) {
                Icon(Icons.Filled.Add, null, tint = T.btnInk, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(4.dp))
                Text(tr("創作範圍"), color = T.btnInk, style = ff(FF.Subheadline, FontWeight.SemiBold))
            }
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (groups.isEmpty()) item {
                Txt(tr("還沒有影片詞組。在 Safari 查詞的影片字幕裡選的詞，傳到 App 的時候會照影片分組放在這裡。"), ff(FF.Body), T.muted, Modifier.padding(8.dp))
            }
            // (a 範圍: its name, then each of its groups, still apart)
            for (f in Store.groupFolders) {
                item(key = "f|$f") { ScopeHeader(f) }
                for (g in Store.folderGroups(f)) item(key = "fg|$f|$g") { GroupCard(g, true, { renaming = g }, { deleting = g }) }
            }
            items(groups.filter { Store.groupFolderList(it).isEmpty() }, key = { "g|$it" }) { g -> GroupCard(g, false, { renaming = g }, { deleting = g }) }
            item { Spacer(Modifier.height(40.dp)) }
        }
    }
    renaming?.let { g ->
        var name by remember(g) { mutableStateOf(Store.groupName(g)) }
        AlertDialog(onDismissRequest = { renaming = null }, containerColor = T.fn,
            title = { Txt(tr("改名"), ff(FF.Headline)) },
            text = { OutlinedTextField(name, { name = it }, singleLine = true, label = { Text(tr("名字")) }) },
            confirmButton = { TextButton(onClick = { if (name.isNotBlank()) Store.renameGroup(g, name.trim()); renaming = null }) { Text(tr("好"), color = T.btnInk) } },
            dismissButton = { TextButton(onClick = { renaming = null }) { Text(tr("取消"), color = T.muted) } })
    }
    deleting?.let { g ->
        AlertDialog(onDismissRequest = { deleting = null }, containerColor = T.fn,
            title = { Txt(tr("刪掉這個影片詞組？"), ff(FF.Headline)) },
            confirmButton = { TextButton(onClick = { Store.deleteGroup(g); deleting = null }) { Text(tr("刪掉詞組（詞留在不熟）"), color = T.rustInk) } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text(tr("取消"), color = T.muted) } })
    }
}

/** a 範圍: its name, how many groups and words, and 練習 / 編輯 / 刪掉 */
@Composable
private fun ScopeHeader(f: String) {
    val nav = LocalNav.current
    val gs = Store.folderGroups(f)
    val n = gs.flatMap { Store.groupKeys(it) }.distinct().count { Lang.kind(it) == Store.lang }
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(top = 10.dp, start = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Filled.Layers, null, tint = T.oliveInk)
        Column(Modifier.weight(1f)) {
            Txt(f, ff(FF.Title3, FontWeight.Bold), T.glyph)
            Txt(tr("{0} 個影片詞組・{1} 個詞", gs.size, n), ff(FF.Caption), T.muted)
        }
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreHoriz, null, tint = T.oliveInk) }
            DropdownMenu(menu, { menu = false }, containerColor = T.fn) {
                DropdownMenuItem(text = { Text(tr("練習這個範圍"), color = T.glyph) }, leadingIcon = { Icon(Icons.Filled.School, null, tint = T.glyph) },
                    onClick = { Store.practiceGroup = "folder:$f"; menu = false; nav.pop() })
                DropdownMenuItem(text = { Text(tr("編輯（名字、詞組）"), color = T.glyph) }, leadingIcon = { Icon(Icons.Filled.Edit, null, tint = T.glyph) },
                    onClick = { menu = false; nav.push(Route.ScopeEditor(f)) })
                DropdownMenuItem(text = { Text(tr("刪掉範圍（詞組留著）"), color = T.rustInk) }, leadingIcon = { Icon(Icons.Filled.Delete, null, tint = T.rustInk) },
                    onClick = { Store.deleteFolder(f); menu = false })
            }
        }
    }
}

/** one group: its name, date and counts, its menu, and its words (swipe one away to take it out of the group) */
@Composable
private fun GroupCard(g: String, inScope: Boolean, rename: () -> Unit, delete: () -> Unit) {
    val nav = LocalNav.current
    val uri = LocalUriHandler.current
    val goal = Prefs.goal.value
    val keys = Store.groupKeys(g).filter { Lang.kind(it) == Store.lang }
    val unknown = keys.count { Store.wordStatus(it) == 2 }
    var menu by remember { mutableStateOf(false) }
    Column(Modifier.padding(start = if (inScope) 14.dp else 0.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.Movie, null, tint = T.btnInk, modifier = Modifier.size(18.dp))
            Column(Modifier.weight(1f)) {
                Txt(Store.groupName(g), ff(FF.Headline), T.glyph, maxLines = 2)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Txt(dateText(Store.groupDate(g)), ff(FF.Caption), T.muted)
                    Txt(tr("{0} 個詞・不熟 {1}", keys.size, unknown), ff(FF.Caption), T.muted)
                    if (Store.practiceGroup == g) Txt(tr("練習範圍"), ff(FF.Caption), T.greenInk)
                }
            }
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreHoriz, null, tint = T.btnInk) }
                DropdownMenu(menu, { menu = false }, containerColor = T.fn) {
                    DropdownMenuItem(text = { Text(tr("練習這一組"), color = T.glyph) }, leadingIcon = { Icon(Icons.Filled.School, null, tint = T.glyph) },
                        onClick = { Store.practiceGroup = g; menu = false; nav.pop() })
                    Store.groupURL(g)?.let { u ->
                        DropdownMenuItem(text = { Text(tr("打開影片"), color = T.glyph) }, leadingIcon = { Icon(Icons.Filled.PlayCircle, null, tint = T.glyph) },
                            onClick = { menu = false; try { uri.openUri(u) } catch (_: Exception) {} })
                    }
                    DropdownMenuItem(text = { Text(tr("改名"), color = T.glyph) }, leadingIcon = { Icon(Icons.Filled.Edit, null, tint = T.glyph) },
                        onClick = { menu = false; rename() })
                    DropdownMenuItem(text = { Text(tr("刪掉詞組"), color = T.rustInk) }, leadingIcon = { Icon(Icons.Filled.Delete, null, tint = T.rustInk) },
                        onClick = { menu = false; delete() })
                }
            }
        }
        if (keys.isNotEmpty()) ListCard {
            keys.forEachIndexed { i, k ->
                if (i > 0) RowDivider()
                val c = Store.cardFor(k)
                SwipeRow(start = null, end = Pair(tr("移出詞組"), T.rustEdge), onStart = {}, onEnd = { Store.removeFromGroup(g, k) },
                    onClick = { if (c != null) UI.open(Sheet.CardSheet(c)) }) {
                    if (c != null) WordRow(c, Store.streak(c), goal)
                    else Txt(k.substringBefore("\t"), ff(FF.Body), T.glyph, Modifier.padding(14.dp))
                }
            }
        }
    }
}

/** 創作範圍 / 編輯範圍: a name, then tick the 影片詞組 it's made of */
@Composable
fun ScopeEditorPage(editing: String?, onBack: () -> Unit) {
    Store.rev
    val groups = Store.groupIds
    var name by remember(editing) { mutableStateOf(editing ?: "") }
    val picked = remember(editing) { mutableStateListOf<String>().apply { if (editing != null) addAll(Store.folderGroups(editing)) } }
    var deleting by remember { mutableStateOf(false) }
    val ok = name.isNotBlank() && picked.isNotEmpty()
    Column(Modifier.fillMaxSize()) {
        TopBar(if (editing == null) tr("創作範圍") else tr("編輯範圍"), onBack, settings = false) {
            TextButton(onClick = {
                Store.saveFolder(editing, name.trim(), picked.toSet())
                Store.practiceGroup = "folder:" + name.trim()
                onBack()
            }, enabled = ok) { Text(tr("完成"), color = if (ok) T.btnInk else T.muted, style = ff(FF.Headline)) }
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item {
                SectionTitle(tr("名字"))
                OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), singleLine = true,
                    placeholder = { Text(tr("名字（例如劇名）"), color = T.muted) })
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { SectionTitle(tr("要放進去的影片詞組")) }
                    if (groups.isNotEmpty()) TextButton(onClick = {
                        if (picked.size == groups.size) picked.clear() else { picked.clear(); picked.addAll(groups) }
                    }) { Text(if (picked.size == groups.size) tr("全部不選") else tr("全部選"), color = T.btnInk) }
                }
                if (groups.isEmpty()) Txt(tr("還沒有影片詞組。在 Safari 查詞的影片字幕裡選的詞，傳到 App 的時候會照影片分組放在這裡。"), ff(FF.Body), T.muted, Modifier.padding(8.dp))
            }
            items(groups, key = { "s|$it" }) { g ->
                val on = g in picked
                val n = Store.groupKeys(g).count { Lang.kind(it) == Store.lang }
                val others = Store.groupFolderList(g).filter { it != editing }
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(if (on) T.green.copy(alpha = 0.35f) else T.fn.copy(alpha = 0.7f))
                    .clickable { if (on) picked.remove(g) else picked.add(g) }.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(if (on) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (on) T.greenInk else T.muted)
                    Column(Modifier.weight(1f)) {
                        Txt(Store.groupName(g), ff(FF.Body), T.glyph, maxLines = 2)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Txt(dateText(Store.groupDate(g)), ff(FF.Caption), T.muted)
                            Txt(tr("{0} 個詞", n), ff(FF.Caption), T.muted)
                            // (the other 範圍 it's in already)
                            if (others.isNotEmpty()) Txt(others.joinToString("、"), ff(FF.Caption), T.muted, maxLines = 1)
                        }
                    }
                }
            }
            item { Txt(tr("選了 {0} 組。一個詞組可以放在好幾個範圍裡。", picked.size), ff(FF.Footnote), T.muted, Modifier.padding(4.dp)) }
            if (editing != null) item {
                TextButton(onClick = { deleting = true }) { Text(tr("刪掉「{0}」（詞組留著）", editing), color = T.rustInk) }
            }
            item { Spacer(Modifier.height(40.dp)) }
        }
    }
    if (deleting && editing != null) AlertDialog(onDismissRequest = { deleting = false }, containerColor = T.fn,
        title = { Txt(tr("刪掉這個範圍？"), ff(FF.Headline)) },
        confirmButton = { TextButton(onClick = { Store.deleteFolder(editing); deleting = false; onBack() }) { Text(tr("刪掉範圍（詞組留著）"), color = T.rustInk) } },
        dismissButton = { TextButton(onClick = { deleting = false }) { Text(tr("取消"), color = T.muted) } })
}
