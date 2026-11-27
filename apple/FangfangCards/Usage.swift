import SwiftUI

// 設定 → 用法及資料來源: what each part of the app can do (用法, here), above the data's sources and licenses
// (AboutSettings). The same text as the Android app's, without its Android-only parts.

enum AppUsage {
    struct Item: Identifiable {
        var id: String { title }
        let title: String
        let text: String
        var icon: String { AppUsage.icons[title] ?? "circle.fill" }
    }
    struct Group: Identifiable {
        var id: String { title }
        let title: String
        let items: [Item]
        var icon: String { AppUsage.icons[title] ?? "square.grid.2x2" }
    }
    /// each group's and tile's symbol
    static let icons: [String: String] = [
        "五個分頁": "square.grid.2x2", "練習（「不熟」）": "figure.run", "詞典": "character.book.closed", "語言": "globe.asia.australia",
        "電台與音樂": "radio", "在 App 外面": "rectangle.portrait.and.arrow.right", "進度和資料": "externaldrive",
        "新詞": "rectangle.stack", "不熟": "questionmark.circle", "熟悉": "checkmark.circle", "轉換": "arrow.left.arrow.right", "設定": "gearshape",
        "練習範圍": "scope", "開始練習": "play.circle", "複習": "arrow.clockwise", "本週學習": "calendar", "滑卡練習": "hand.draw",
        "例句填空・排句子・看字排讀音": "text.badge.checkmark", "聲調練習・聲調色球": "waveform", "翻牌配對・遊戲": "gamecontroller",
        "手寫練習・自由寫字": "pencil.tip", "做到一半": "pause.circle",
        "一次查好幾個詞": "text.magnifyingglass", "用華語找台語": "arrow.triangle.branch", "依常用度列出・分類": "list.bullet", "部首查字": "square.split.2x2",
        "收藏・自訂": "bookmark", "腔口・在地詞（台語）": "map", "漢字卡": "character", "複製意思": "doc.on.doc",
        "台語": "t.circle", "華語": "h.circle", "粵語": "y.circle", "客語": "k.circle", "日語": "j.circle", "瑞典語": "s.circle", "英語": "e.circle", "每個語言分開": "square.split.1x2",
        "電台": "radio", "音樂": "music.note", "歌詞": "music.note.list", "歌詞條": "rectangle.bottomhalf.inset.filled", "收藏和歌單": "music.note.house",
        "自己的歌詞": "pencil.and.list.clipboard",
        "捷徑和 Siri": "square.stack.3d.up", "Safari 查詞": "safari", "影片字幕": "captions.bubble",
        "備份與同步": "arrow.triangle.2.circlepath", "匯出與匯入": "square.and.arrow.up", "外觀": "paintpalette",
    ]
    static let intro = "方方詞卡是學台語、華語、粵語、客語、日語、瑞典語和英語的詞卡 App。下面是每個部分能做什麼，最下面是資料的來源和授權。"
    static let groups: [Group] = [
        Group(title: "五個分頁", items: [
            Item(title: "新詞", text: "一張一張滑詞卡：往右＝認識（放到「熟悉」），往左＝不熟（放到「不熟」去練習）。右上角的選單選從哪些詞開始：常用度、分類、HSK／TOCFL 等級或漢字卡。↺ 復原上一張。"),
            Item(title: "不熟", text: "還在學的詞和所有的練習：上面選練習範圍，下面是本週學習、要複習的詞和每一種練習。列表往右滑直接移到「熟悉」，往左滑移回「新詞」。"),
            Item(title: "詞典", text: "查詞：漢字、羅馬字、注音、方音或英文都可以（台語可以用 * 和 ?：人* 是人開頭的詞）。詞條有讀音、意思、例句、發音和常用度，上面有「加到不熟」和「認識」。還有分類、依常用度列出、部首查字、收藏和自訂的詞。"),
            Item(title: "熟悉", text: "已經學會的詞。「卡片複習」把它們再滑一次（往左的回到「不熟」）；「學習進度」看每個等級或分組學了多少，和認識的漢字。"),
            Item(title: "轉換", text: "把一段文字寫成讀音：台語漢字 ⇄ 皓羅 ⇄ 方音（也讀台羅、白話字），華語寫成拼音或注音。點一個詞可以查、收藏、加到「不熟」；「唸出來」用台語語音唸整段。「讀音」把一個詞的台語、華語、粵語、客語讀音並排；「歌詞」是電台或音樂正在放的歌。輸入框旁邊的 ✦ 開關顏色光暈（很長的文字關掉比較順）。"),
            Item(title: "設定", text: "每個分頁右上角的 ⚙︎：語言、讀音和拼寫、腔口、顏色和主題、卡片與練習、聲音、備份、匯出與匯入、詞典資料。"),
        ]),
        Group(title: "練習（「不熟」）", items: [
            Item(title: "練習範圍", text: "選要練哪些詞：全部不熟的詞、一個等級（HSK、TOCFL、常用詞分組、常用度）、漢字等級、一部影片的詞（影片詞組），或用好幾個影片詞組做成的範圍（「創作範圍」）。每一種練習都只用範圍裡的詞，每個語言各記一個。"),
            Item(title: "開始練習", text: "各種題目混在一起：看意思選詞、看詞選意思、聽發音選詞、例句填空、看漢字選讀音、寫字題。連續答對幾次（設定裡可以改）就學會，移到「熟悉」。"),
            Item(title: "複習", text: "學會的詞過一段時間會回來複習（1 天、3 天，然後越來越久）；忘了就回到「不熟」。「練習統計」看每天練了多少、哪些詞什麼時候回來。"),
            Item(title: "本週學習", text: "選這個星期要學的詞，練一個星期，最後做期末測驗；答錯的詞可以留到下一週。"),
            Item(title: "滑卡練習", text: "像「新詞」一樣滑卡片，但往右算答對、往左算答錯，和其他練習一樣慢慢學會。"),
            Item(title: "例句填空・排句子・看字排讀音", text: "只做例句填空；把打亂的例句照意思排回去；只看漢字，把讀音照順序排好。"),
            Item(title: "聲調練習・聲調色球", text: "聽發音，從只有聲調不一樣的拼法裡選對的；聽一個詞，照每個字的聲調點顏色球。"),
            Item(title: "翻牌配對・遊戲", text: "翻兩張牌，把漢字和它的讀音配起來；詞或讀音從上面掉下來，在掉到底以前點對的那一個。"),
            Item(title: "手寫練習・自由寫字", text: "看字、讀音和意思，用手指或 Apple Pencil 在米字格裡寫，可以描著寫（看描得多像）；自由寫字是一整張格子，打一句話來描，像練書法。華語還有「四字格手寫」：照意思把一整個四字格寫出來。"),
            Item(title: "做到一半", text: "練到一半關掉練習或 App，下次會接著上次的題目做。"),
        ]),
        Group(title: "詞典", items: [
            Item(title: "一次查好幾個詞", text: "打一個詞典沒有的長詞（陰謀論），會自己拆成詞典有的詞（陰謀、論）；也可以用空格分開。"),
            Item(title: "依常用度列出・分類", text: "照常用度（五格，越多越常用）或教育部辭典的分類看詞，一次把新詞加到「不熟」。"),
            Item(title: "用華語找台語", text: "在台語的詞典查一個詞，也會用華語詞典的近義詞找：查「幫忙」也找得到解釋寫「幫助」的台語詞（華語詞典裝了的話）。"),
            Item(title: "部首查字", text: "點一個部首找字，或點好幾個部首（氵＋毋 → 海）找有這些部首的字。"),
            Item(title: "收藏・自訂", text: "收藏的詞可以匯出 CSV；自己加的詞（漢字和讀音）用紫色「自訂」標示，跟著備份，也可以匯出成 CSV，選要用哪一種拼寫（匯入的時候認得「意思」「例句」欄）。"),
            Item(title: "腔口・在地詞（台語）", text: "選一個地方（鹿港、臺北、宜蘭、臺南、高雄…）的腔口，卡片、詞典和例句都用那裡的讀音；例句裡當地另外的講法用粉紅色標出來，可以換進句子。只在幾個地方說的方言詞只列那些地方。"),
            Item(title: "漢字卡", text: "每個字的讀音、意思、部首和筆畫，也可以當卡片學；熟悉的詞裡的字會自己算認識。"),
            Item(title: "複製意思", text: "每個意思旁邊的複製按鈕，照設定裡選的格式複製（例如貼到 Anki 或筆記）。"),
        ]),
        Group(title: "語言", items: [
            Item(title: "台語", text: "教育部《臺灣台語常用詞辭典》的詞，用皓羅、台羅、白話字或方音寫；十個地方的腔口，聲調顏色照說出來的變調。方音的第一聲符號可以拿掉，或換成空格（設定 → 語言與讀音 → 台語）。"),
            Item(title: "華語", text: "《兩岸常用詞典》約 10 萬個詞；卡片照 HSK 3.0 或 TOCFL；拼音或注音，臺灣或大陸讀音；詞類、近反義詞、英文解釋。"),
            Item(title: "粵語", text: "粵拼、意思、英文解釋和漢字卡。"),
            Item(title: "客語", text: "教育部《臺灣客語辭典》的詞，六個腔（四縣、海陸、大埔、饒平、詔安、南四縣）的讀音，拼音或注音。"),
            Item(title: "日語", text: "用漢字、假名、羅馬字或英文查（變化過的形也找得到）；活用表、漢字卡（音讀、訓讀）、助詞的說明和練習，「實驗室」把語尾一個一個接上去看意思。"),
            Item(title: "瑞典語", text: "每個詞分成詞素上色（詞根、前綴、後綴、詞尾），有中文和英文解釋；詞典沒有的詞照構詞規則推算。"),
            Item(title: "英語", text: "ECDICT 的詞：英文、中文和瑞典文解釋（設定裡選要顯示哪些），英式和美式 IPA，變化形也查得到（ran → run）。卡片可以照詞頻、Collins 星級或考試詞表（中考到 GRE）分等級。"),
            Item(title: "每個語言分開", text: "每個語言的新詞、不熟、熟悉和練習範圍分開記，都在同一個進度檔裡。詞典在「設定 → 詞典資料」安裝。"),
        ]),
        Group(title: "電台與音樂", items: [
            Item(title: "電台", text: "上面的收音機按鈕：一邊練習一邊聽各個語言的廣播（背景和鎖定畫面也繼續播），有睡眠定時和電台鬧鐘，音量和詞的發音分開。電台有送歌名的話會自己找歌詞。"),
            Item(title: "音樂", text: "收音機按鈕裡的「音樂」：找歌來放。有 Apple Music 的話整首歌都能聽，沒有的話是 30 秒的試聽（Mac 上只有試聽）。開始放歌電台就停，反過來也一樣。"),
            Item(title: "歌詞", text: "在「轉換 → 歌詞」：漢字和讀音並排，點詞就查、收藏、加到不熟（那一行跟著存）。有時間的歌詞會跟著歌走，正在唱的詞會變大；「對時」±¼ 秒、±1 秒，⏮ ⏭ 跳一行，清單裡點一行就從那裡唱。音樂的歌照播放器的時間，不用對時。"),
            Item(title: "歌詞條", text: "放歌的時候，正在唱的那一行浮在每一頁上面（遊戲裡也有），下一行先畫好、往上流進來；點詞就查。拖上面那一排可以移到別的地方（會記住），✕ 這首歌不顯示，✦ 只關歌詞的光暈。"),
            Item(title: "收藏和歌單", text: "歌可以收藏、放進歌單（全部播放、隨機播放，一首放完接下一首）；從 Apple Music 的資料庫勾選歌單匯入。電台裡「我的歌」存的歌，點一下就放（Apple Music 裡有的話）。"),
            Item(title: "自己的歌詞", text: "沒有歌詞或時間不對的歌：自己打（或貼上、或改 LRCLIB 的），再一邊放歌一邊在每一句開始的時候按一下來對時間。可以退一行、點一行重新對、±0.05／0.1 秒微調、加空行；存在裝置上，之後放這首歌都用，也可以分享成 .lrc 檔、或打開 .lrc 檔；有備份資料夾的話，放在裡面的「歌詞」資料夾，各個裝置一起用。"),
        ]),
        Group(title: "在 App 外面", items: [
            Item(title: "捷徑和 Siri", text: "「在方方詞卡查詞」「方方查詞（小視窗）」「方方快速查詞」：在其他 App 裡也能查詞，不用離開。"),
            Item(title: "Safari 查詞", text: "在 Safari（或電腦和 Android 的 Firefox）用 Apple Pencil 或游標停在一個詞上，就跳出它的卡片；選好的詞按「傳到 App」連同那一句話傳回來。"),
            Item(title: "影片字幕", text: "YouTube、Viki 的字幕在旁邊的面板：不認識的詞標讀音和意思、這部影片你懂多少 %、生詞清單、重複和慢速；選的詞照影片分成影片詞組。"),
        ]),
        Group(title: "進度和資料", items: [
            Item(title: "備份與同步", text: "進度存在你選的資料夾（例如 iCloud 雲碟），其他 iPhone、iPad、Mac 也接得上；備份檔在 Android 版也能匯入。"),
            Item(title: "匯出與匯入", text: "把詞匯出成 CSV 或 Anki 的檔案，存或匯入備份檔。"),
            Item(title: "外觀", text: "五種主題、每個聲調的顏色自己選、文字大小，介面可以換成英文。"),
        ]),
    ]
}

/// a grid of tiles, like the add-on's settings page: a group's name over its tiles, as many side by side as fit
struct InfoGrid<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = T.btnInk
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).ffFont(.headline).foregroundStyle(T.glyph)
            }
            .padding(.leading, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                content()
            }
        }
    }
}

/// one tile: a symbol and a name over its text
struct InfoTile: View {
    let title: String
    var icon: String? = nil
    let text: String
    var tint: Color = T.btnInk
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let icon { Image(systemName: icon).foregroundStyle(tint).ffFont(.subheadline) }
                Text(title).ffFont(.subheadline, .semibold).foregroundStyle(T.glyph)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(text).ffFont(.footnote).foregroundStyle(T.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.fnEdge, lineWidth: 1))
    }
}

/// 用法: each group a grid of tiles
struct UsageTiles: View {
    @AppStorage(ToneColors.key) private var toneSys = 0
    var body: some View {
        Text(trs(AppUsage.intro)).ffFont(.subheadline).foregroundStyle(T.glyph)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(T.btnEdge.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.btnEdge.opacity(0.6), lineWidth: 1))
        ForEach(Array(AppUsage.groups.enumerated()), id: \.offset) { n, g in
            let c = Self.tint(n, toneSys)
            InfoGrid(title: trs(g.title), icon: g.icon, tint: c) {
                ForEach(g.items) { it in InfoTile(title: trs(it.title), icon: it.icon, text: trs(it.text), tint: c) }
            }
        }
    }

    /// (with tone colours on, each group one of them, like the settings' tiles)
    static func tint(_ n: Int, _ toneSys: Int) -> Color {
        toneSys != 0 ? (ToneColors.color([1, 2, 3, 5, 7, 8, 4][n % 7], 7) ?? T.btnInk) : T.btnInk
    }
}
