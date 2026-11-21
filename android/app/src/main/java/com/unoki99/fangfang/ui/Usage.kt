package com.unoki99.fangfang.ui

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.engine.Lang
import com.unoki99.fangfang.tr

// 設定 → 用法及資料來源: what each part of the app can do (用法, here), above the data's sources and licenses
// (AboutPage in Settings.kt). The same text as the iPhone app's, without its iPhone-only parts.

object AppUsage {
    class Item(val title: String, val text: String)
    class Group(val title: String, val items: List<Item>)
    const val intro = "方方詞卡是學台語、華語、粵語、客語和日語的詞卡 App。下面是每個部分能做什麼，最下面是資料的來源和授權。"
    /** the computer version's, which has 瑞典語 too */
    const val introComputer = "方方詞卡是學台語、華語、粵語、客語、日語和瑞典語的詞卡 App。下面是每個部分能做什麼，最下面是資料的來源和授權。"
    /** the Android phone's own parts, not on the computer */
    val phoneOnly = setOf("小工具", "鎖定畫面的詞", "方方查詞")
    val groups = listOf(
        Group("五個分頁", listOf(
            Item("新詞", "一張一張滑詞卡：往右＝認識（放到「熟悉」），往左＝不熟（放到「不熟」去練習）。右上角的選單選從哪些詞開始：常用度、分類、HSK／TOCFL 等級或漢字卡。↺ 復原上一張。"),
            Item("不熟", "還在學的詞和所有的練習：上面選練習範圍，下面是本週學習、要複習的詞和每一種練習。列表往右滑直接移到「熟悉」，往左滑移回「新詞」。"),
            Item("詞典", "查詞：漢字、羅馬字、注音、方音或英文都可以（台語可以用 * 和 ?：人* 是人開頭的詞）。詞條有讀音、意思、例句、發音和常用度，上面有「加到不熟」和「認識」。還有分類、依常用度列出、部首查字、收藏和自訂的詞。"),
            Item("熟悉", "已經學會的詞。「卡片複習」把它們再滑一次（往左的回到「不熟」）；「學習進度」看每個等級或分組學了多少，和認識的漢字。"),
            Item("轉換", "把一段文字寫成讀音：台語漢字 ⇄ 皓羅 ⇄ 方音（也讀台羅、白話字），華語寫成拼音或注音。點一個詞可以查、收藏、加到「不熟」；「唸出來」用台語語音唸整段。「讀音」把一個詞的台語、華語、粵語、客語讀音並排。"),
            Item("設定", "每個分頁右上角的 ⚙︎：語言、讀音和拼寫、腔口、顏色和主題、卡片與練習、聲音、備份、匯出與匯入、詞典資料。")
        )),
        Group("練習（「不熟」）", listOf(
            Item("練習範圍", "選要練哪些詞：全部不熟的詞、一個等級（HSK、TOCFL、常用詞分組、常用度）、漢字等級、一部影片的詞（影片詞組），或用好幾個影片詞組做成的範圍（「創作範圍」）。每一種練習都只用範圍裡的詞，每個語言各記一個。"),
            Item("開始練習", "各種題目混在一起：看意思選詞、看詞選意思、聽發音選詞、例句填空、看漢字選讀音、寫字題。連續答對幾次（設定裡可以改）就學會，移到「熟悉」。"),
            Item("複習", "學會的詞過一段時間會回來複習（1 天、3 天，然後越來越久）；忘了就回到「不熟」。「練習統計」看每天練了多少、哪些詞什麼時候回來。"),
            Item("本週學習", "選這個星期要學的詞，練一個星期，最後做期末測驗；答錯的詞可以留到下一週。"),
            Item("滑卡練習", "像「新詞」一樣滑卡片，但往右算答對、往左算答錯，和其他練習一樣慢慢學會。"),
            Item("例句填空・排句子・看字排讀音", "只做例句填空；把打亂的例句照意思排回去；只看漢字，把讀音照順序排好。"),
            Item("聲調練習・聲調色球", "聽發音，從只有聲調不一樣的拼法裡選對的；聽一個詞，照每個字的聲調點顏色球。"),
            Item("翻牌配對・遊戲", "翻兩張牌，把漢字和它的讀音配起來；詞或讀音從上面掉下來，在掉到底以前點對的那一個。"),
            Item("手寫練習・自由寫字", "看字、讀音和意思，用手指或觸控筆在米字格裡寫，可以描著寫（看描得多像）；自由寫字是一整張格子，打一句話來描，像練書法。"),
            Item("做到一半", "練到一半關掉練習或 App，下次會接著上次的題目做。")
        )),
        Group("詞典", listOf(
            Item("一次查好幾個詞", "打一個詞典沒有的長詞（陰謀論），會自己拆成詞典有的詞（陰謀、論）；也可以用空格分開。"),
            Item("依常用度列出・分類", "照常用度（五格，越多越常用）或教育部辭典的分類看詞，一次把新詞加到「不熟」。"),
            Item("部首查字", "點一個部首找字，或點好幾個部首（氵＋毋 → 海）找有這些部首的字。"),
            Item("收藏・自訂", "收藏的詞可以匯出 CSV；自己加的詞（漢字和讀音）用紫色「自訂」標示，跟著備份。"),
            Item("腔口・在地詞（台語）", "選一個地方（鹿港、臺北、宜蘭、臺南、高雄…）的腔口，卡片、詞典和例句都用那裡的讀音；例句裡當地另外的講法用粉紅色標出來，可以換進句子。"),
            Item("漢字卡", "每個字的讀音、意思、部首和筆畫，也可以當卡片學；熟悉的詞裡的字會自己算認識。"),
            Item("複製意思", "每個意思旁邊的複製按鈕，照設定裡選的格式複製（例如貼到 Anki 或筆記）。")
        )),
        Group("語言", listOf(
            Item("台語", "教育部《臺灣台語常用詞辭典》的詞，用皓羅、台羅、白話字或方音寫；十個地方的腔口，聲調顏色照說出來的變調。"),
            Item("華語", "《兩岸常用詞典》約 10 萬個詞；卡片照 HSK 3.0 或 TOCFL；拼音或注音，臺灣或大陸讀音；詞類、近反義詞、英文解釋。"),
            Item("粵語", "粵拼、意思、英文解釋和漢字卡。"),
            Item("客語", "教育部《臺灣客語辭典》的詞，六個腔（四縣、海陸、大埔、饒平、詔安、南四縣）的讀音，拼音或注音。"),
            Item("日語", "用漢字、假名、羅馬字或英文查（變化過的形也找得到）；活用表、漢字卡（音讀、訓讀）、助詞的說明和練習，「實驗室」把語尾一個一個接上去看意思。"),
            Item("每個語言分開", "每個語言的新詞、不熟、熟悉和練習範圍分開記，都在同一個進度檔裡。詞典在「設定 → 詞典資料」安裝。")
        )),
        Group("在 App 外面", listOf(
            Item("小工具", "主畫面上的詞卡，每個鐘頭換一個詞：聽發音、收藏、標成熟悉或換下一個。"),
            Item("鎖定畫面的詞", "離開 App 的時候，一個安靜的通知（鎖定畫面也看得到）顯示練習範圍裡一個不熟的詞和讀音；點一下打開它的詞條。"),
            Item("方方查詞", "在任何 App 選取文字，選單裡按「方方查詞」，就在那個 App 上面跳出一張小卡片。"),
            Item("瀏覽器查詞（Firefox）", "在 Firefox 用游標停在一個詞上（或選取它），就跳出它的卡片；選好的詞按「傳到 App」連同那一句話傳回來。"),
            Item("影片字幕", "YouTube、Viki 的字幕在旁邊的面板：不認識的詞標讀音和意思、這部影片你懂多少 %、生詞清單、重複和慢速；選的詞照影片分成影片詞組。"),
            Item("電台和歌詞", "一邊練習一邊聽各個語言的廣播（背景和鎖定畫面也繼續播）；電台有送歌名的話顯示歌詞，點詞就查。")
        )),
        Group("進度和資料", listOf(
            Item("備份與同步", "進度自動備份到你選的資料夾；備份檔在 iPhone 版也能匯入。"),
            Item("匯出與匯入", "把詞匯出成 CSV 或 Anki 的檔案，存或匯入備份檔。"),
            Item("外觀", "五種主題、每個聲調的顏色自己選、文字大小，介面可以換成英文。")
        ))
    )
}

/** 用法: the groups, each a panel of its own */
@Composable
fun UsageSections() {
    SectionTitle(tr("用法"))
    ListCard {
        Txt(tr(if (Lang.count > 5) AppUsage.introComputer else AppUsage.intro), ff(FF.Subheadline), T.glyph, Modifier.padding(14.dp))
    }
    // (the computer version: no home screen, lock screen or text-selection menu, so not those parts)
    val computer = Lang.count > 5
    for (g in AppUsage.groups) {
        val items = if (computer) g.items.filter { it.title !in AppUsage.phoneOnly } else g.items
        if (items.isEmpty()) continue
        SectionTitle(tr(g.title))
        ListCard {
            items.forEachIndexed { i, item ->
                if (i > 0) RowDivider()
                Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Txt(tr(item.title), ff(FF.Subheadline, androidx.compose.ui.text.font.FontWeight.SemiBold), T.glyph)
                    Txt(tr(item.text), ff(FF.Footnote), T.muted)
                }
            }
        }
    }
}
