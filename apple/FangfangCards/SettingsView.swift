import SwiftUI
import UniformTypeIdentifiers

// MARK: - 設定: a grid of topics; each opens its own page

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage(ToneColors.key) private var toneSys = 0
    @AppStorage(AppTheme.key) private var theme = AppTheme.night.rawValue
    /// (the pages here are written again in the other language right away)
    @AppStorage(UILang.key) private var uiLangNow = 0
    @AppStorage("goal") private var goal = 3
    @AppStorage("sessionSize") private var sessionSize = 10
    @AppStorage("autoPlay") private var autoPlay = false
    @AppStorage("volume") private var volume = 0.8
    @AppStorage(InputCodes.onKey) private var imeOn = false
    @AppStorage("wordGap") private var wordGap = true
    @AppStorage(SenseCopy.tplKey) private var copyTpl = SenseCopy.presets[0].tpl
    @AppStorage(SenseCopy.exKey) private var copyEx = SenseCopy.presets[0].ex
    @AppStorage(SenseCopy.sepKey) private var copySep = SenseCopy.presets[0].sep
    @AppStorage(SenseCopy.zhTplKey) private var zhCopyTpl = SenseCopy.zhPresets[0].tpl
    @AppStorage(SenseCopy.zhExKey) private var zhCopyEx = SenseCopy.zhPresets[0].ex
    @AppStorage(SenseCopy.zhSepKey) private var zhCopySep = SenseCopy.zhPresets[0].sep

    private struct Topic: Identifiable {
        let id: Int
        let title: String
        let icon: String
        let summary: String
    }

    private var topics: [Topic] {
        let themeName = (AppTheme(rawValue: theme) ?? .night).name
        let tones = toneSys == 0 ? trs("聲調顏色關") : (store.lang != 0 && store.lang != 3 ? trs("聲調顏色開") : (toneSys == 7 ? trs("七聲") : trs("五聲")))
        let lang: String = store.isSv
            ? trs("瑞典語") + "・" + trs(Lang.romNames[min(max(store.zhRom, 0), 1)])
            : store.isJa
            ? trs("日語") + "・" + trs(Lang.romNames[min(max(store.zhRom, 0), 1)])
            : store.isYue
            ? trs("粵語") + "・" + trs(Lang.romNames[min(max(store.zhRom, 0), 1)])
            : store.isHak
            ? trs("客語") + "・" + trs(Lang.romNames[min(max(store.zhRom, 0), 1)]) + "・" + trs(Lang.hakAccents[min(max(store.hakAccent, 0), Lang.hakAccents.count - 1)])
            : store.isZh
            ? trs("華語") + "・" + trs(Lang.romNames[min(max(store.zhRom, 0), 1)]) + "・" + trs(Lang.zhPlaceNames[min(max(store.zhPlace, 0), Lang.zhPlaceNames.count - 1)]) + "・" + Lang.listNames[min(max(store.zhList, 0), 1)]
            : trs("台語") + "・" + trs(ROM_NAMES[TwRom.lat(rom)]) + "・" + (place >= 0 && place < PLACE_NAMES.count ? trs(String(PLACE_NAMES[place].prefix(2))) : trs("通行"))
        let _ = copyTpl + copyEx + zhCopyTpl + zhCopyEx + "\(copySep)\(zhCopySep)"   // redraw when a layout changes
        let copyStyle = SenseCopy.styleName(zh: store.isZh)
        return [
            Topic(id: 0, title: tr("顏色與外觀"), icon: "paintpalette", summary: tr("\(themeName)・\(tones)")),
            Topic(id: 1, title: tr("語言與讀音"), icon: "character.bubble", summary: lang),
            Topic(id: 2, title: tr("卡片與練習"), icon: "rectangle.stack", summary: tr("答對 \(goal) 次・每次 \(sessionSize) 個")),
            Topic(id: 3, title: tr("詞典"), icon: "character.book.closed", summary: tr("複製：\(copyStyle)・拆碼\(imeOn ? trs("開") : trs("關"))")),
            Topic(id: 4, title: tr("聲音"), icon: "speaker.wave.2", summary: tr("自動播放\(autoPlay ? trs("開") : trs("關"))・音量 \(Int((volume * 100).rounded()))%")),
            Topic(id: 5, title: tr("備份與同步"), icon: "arrow.triangle.2.circlepath", summary: store.backupFolderName ?? trs("還沒設定")),
            Topic(id: 8, title: tr("詞典資料"), icon: "arrow.down.circle", summary: tr("安裝、移除詞典")),
            Topic(id: 6, title: tr("匯出與匯入"), icon: "square.and.arrow.up", summary: tr("CSV・備份檔")),
            Topic(id: 7, title: tr("關於與資料來源"), icon: "info.circle", summary: tr("資料、授權")),
        ]
    }

    var body: some View {
        let _ = uiLangNow
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(topics) { t in
                    NavigationLink { page(t.id).environmentObject(store) } label: { tile(t) }
                        .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle(tr("設定"))
    }

    @ViewBuilder private func page(_ id: Int) -> some View {
        switch id {
        case 0: LookSettings()
        case 1: LanguageSettings()
        case 2: PracticeSettings()
        case 3: DictionarySettings()
        case 4: SoundSettings()
        case 5: BackupSettings()
        case 6: ExportSettings()
        case 8: DictDataSettings()
        default: AboutSettings()
        }
    }

    /// with tone colours on, each topic is one of the tone colours (a little surprise)
    private func tint(_ id: Int) -> Color? {
        guard toneSys != 0 else { return nil }
        // (詞典資料 yellow, 匯出與匯入 pink, 關於與資料來源 grey; the others the tone colours in turn)
        switch id {
        case 8: return Color(hex: 0xffe066)
        case 6: return Color(hex: 0xff8cc6)
        case 7: return Color(hex: 0xa3a3a8)
        default: break
        }
        return ToneColors.color([1, 2, 3, 4, 5, 6, 7, 8][id % 8], 7)
    }

    private func tile(_ t: Topic) -> some View {
        let c = tint(t.id)
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: t.icon)
                .ffFont(.title3, .semibold)
                .foregroundStyle(c ?? T.oliveInk)
            Text(t.title).ffFont(.headline).foregroundStyle(c ?? T.glyph)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(t.summary).ffFont(.caption).foregroundStyle(T.muted)
                .lineLimit(2).multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(c.map { $0.opacity(0.16) } ?? T.fn.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.map { $0.opacity(0.7) } ?? T.fnEdge, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// every topic page looks the same: a Form on the app's background
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        Form { content() }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: 顏色與外觀

private struct LookSettings: View {
    @EnvironmentObject var store: Store
    @AppStorage(AppTheme.key) private var theme = AppTheme.night.rawValue
    @AppStorage(ToneColors.key) private var toneSys = 0
    @AppStorage(ToneColors.marksKey) private var toneMarks = false
    @AppStorage(ToneColors.glowKey) private var toneGlow = ToneColors.glowStandard
    @AppStorage(ToneColors.versionKey) private var colorVersion = 0
    private let glassOn = false   // the Liquid Glass look was taken out
    @AppStorage(SwellTest.key) private var swellOn = SwellTest.standard
    @AppStorage(TextSize.key) private var textSize = TextSize.standard
    @AppStorage("widgetBG") private var widgetBG = 0.45
    @AppStorage(ThemeMotion.key) private var themeMotion = true
    @AppStorage(DictFont.key) private var dictFont = 0
    @State private var fontReady = true

    var body: some View {
        SettingsPage(title: tr("顏色與外觀")) {
            // 字體: the app's 漢字 and kana in the system font or a handwriting font
            Section {
                Picker(tr("字體"), selection: $dictFont) {
                    ForEach(Array(DictFont.names.enumerated()), id: \.offset) { i, n in Text(trs(n)).tag(i) }
                }
                // a preview in the font chosen
                Text(tr("方方詞卡・漢字 かな Abc"))
                    .font(DictFont.font(22) ?? .system(size: 22))
                    .id("\(dictFont)\(fontReady)")
            } header: {
                Text(tr("字體"))
            } footer: {
                Text(tr("整個 App 的漢字和假名用系統字體或手寫練習的字體；英文和拼音不變。楷體第一次要從 Apple 下載（要網路）。"))
            }
            .onChange(of: dictFont) {
                // (Apple's 楷體 is downloaded the first time; the others are in the app)
                if dictFont == 1 { fontReady = false; Kaiti.prepare { _ in fontReady = true } }
            }
            Section {
                Picker(tr("主題"), selection: $theme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.name).tag($0.rawValue) }
                }
                .pickerStyle(.menu)
                Toggle(tr("主題動畫"), isOn: $themeMotion)
            } footer: {
                Text(tr("關掉的話，主題的背景（螢火蟲、星星、雪）和藥水條都不會動，比較省電。"))
            }
            // 日語: no tones; kanji, hiragana, katakana, particles and endings each in a colour
            if store.isSv {
                Section {
                    Toggle(tr("詞素顏色"), isOn: Binding(get: { toneSys != 0 }, set: { toneSys = $0 ? (toneSys == 0 ? 7 : toneSys) : 0 }))
                    if toneSys != 0 { Toggle(tr("顏色光暈"), isOn: $toneGlow) }
                    NavigationLink { ToneColorPicker(set: 5).environmentObject(store) } label: {
                        HStack {
                            Text(tr("選瑞典語的顏色"))
                            Spacer()
                            HStack(spacing: 3) {
                                ForEach(0..<SvColors.keys.count, id: \.self) { i in Circle().fill(SvColors.color(i)).frame(width: 7, height: 7) }
                            }
                        }
                    }
                } header: {
                    Text(tr("詞素顏色"))
                } footer: {
                    Text(tr("瑞典語：詞根黃（複合詞的第二個詞根橘）、前綴青、後綴粉紅、連接音灰、詞尾紫。"))
                }
            } else if store.isJa {
                Section {
                    Toggle(tr("文字顏色"), isOn: Binding(get: { toneSys != 0 }, set: { toneSys = $0 ? (toneSys == 0 ? 7 : toneSys) : 0 }))
                    if toneSys != 0 { Toggle(tr("顏色光暈"), isOn: $toneGlow) }
                    NavigationLink { ToneColorPicker(set: 4).environmentObject(store) } label: {
                        HStack {
                            Text(tr("選日語的顏色"))
                            Spacer()
                            HStack(spacing: 3) {
                                ForEach(0..<JaColors.keys.count, id: \.self) { i in Circle().fill(JaColors.color(i)).frame(width: 7, height: 7) }
                            }
                        }
                    }
                } header: {
                    Text(tr("文字顏色"))
                } footer: {
                    Text(tr("日語：漢字黃、平假名綠、片假名藍、助詞紅、語尾（助動詞）紫。"))
                }
            } else {
            Section {
                if store.lang == 0 || store.lang == 3 {
                    Picker(tr("聲調顏色"), selection: $toneSys) {
                        Text(tr("關")).tag(0)
                        Text(tr("七聲")).tag(7)
                        Text(tr("五聲")).tag(5)
                    }
                    .pickerStyle(.segmented)
                } else {
                    // (七聲 / 五聲 are 台語's: the other languages only turn the colours on and off)
                    Toggle(tr("聲調顏色"), isOn: Binding(get: { toneSys != 0 }, set: { toneSys = $0 ? (toneSys == 0 ? 7 : toneSys) : 0 }))
                }
                if toneSys != 0 {
                    Toggle(tr("聲調光暈"), isOn: $toneGlow)
                    if store.lang == 0 { Toggle(tr("聲調符號照變調寫"), isOn: $toneMarks) }
                }
                NavigationLink { ToneColorPicker().environmentObject(store) } label: {
                    HStack {
                        Text(tr("選聲調顏色"))
                        Spacer()
                        HStack(spacing: 3) {
                            ForEach(ToneColors.twTones, id: \.self) { t in
                                Circle().fill(Color(hex: ToneColors.hex(zh: false, t))).frame(width: 7, height: 7)
                            }
                        }
                    }
                }
            } header: {
                Text(tr("聲調顏色"))
            } footer: {
                Text(tr("原本的顏色：華語一聲紅、二聲綠、三聲藍、四聲紫、輕聲灰。在「選聲調顏色」可以換台語和華語每個聲調的顏色。"))
            }
            }
            if TextSize.onThisDevice {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "textformat.size.smaller").foregroundStyle(T.muted)
                        Slider(value: Binding(get: { Double(TextSize.clamp(textSize)) },
                                              set: { textSize = TextSize.clamp(Int($0.rounded())) }),
                               in: 0...Double(TextSize.levels.count - 1), step: 1)
                        Image(systemName: "textformat.size.larger").foregroundStyle(T.muted)
                        Text(TextSize.names[TextSize.clamp(textSize)]).foregroundStyle(T.muted).monospacedDigit()
                    }
                } header: {
                    Text(tr("文字大小"))
                } footer: {
                    Text(tr("鍵盤：⌘+、⌘−、⌘0"))
                }
            }
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "circle.dashed").foregroundStyle(T.muted)
                    Slider(value: $widgetBG, in: 0...1, step: 0.05)
                    Image(systemName: "circle.fill").foregroundStyle(T.muted)
                    Text(widgetBG < 0.05 ? trs("透明") : (widgetBG > 0.95 ? trs("不透明") : "\(Int((widgetBG * 100).rounded()))%"))
                        .foregroundStyle(T.muted).monospacedDigit()
                }
                .onChange(of: widgetBG) { WidgetBridge.settingsChanged(store) }
            } header: {
                Text(tr("小工具背景"))
            }
            SafariLookupSection()
            Section {
                Toggle(tr("畫成圖再放大"), isOn: $swellOn)
            } header: {
                Text(tr("詞放大"))
            } footer: {
                Text(tr("按住或游標移到可以點的詞上面，詞會放大一點。關掉就不放大。"))
            }
        }
    }
}

// MARK: 語言與讀音

private struct LanguageSettings: View {
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    @AppStorage(UILang.key) private var uiLang = 0
    // each of 華語 and 粵語 has its own spelling (the one shown now is also store.zhRom, so the pages redraw)
    @AppStorage("zhRom") private var zhRomSaved = 0
    @AppStorage(Lang.yueRomKey) private var yueRomSaved = 0
    @AppStorage(Lang.hakRomKey) private var hakRomSaved = 0
    @AppStorage(Lang.jaRomKey) private var jaRomSaved = 1
    @AppStorage(Lang.svRomKey) private var svRomSaved = 0
    @AppStorage(SvGuess.key) private var svGuess = true
    @AppStorage(Simp.key) private var simplified = false

    var body: some View {
        SettingsPage(title: tr("語言與讀音")) {
            Section {
                Picker(tr("語言"), selection: Binding(get: { store.lang }, set: { store.setLanguage($0) })) {
                    // (short: six don't fit side by side; English: TW ZH YUE HAK JA SV)
                    ForEach(0..<Lang.count, id: \.self) { i in
                        Text(UILang.english ? ["TW", "ZH", "YUE", "HAK", "JA", "SV"][i] : ["台", "華", "粵", "客", "日", "瑞"][i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(tr("要學的語言"))
            } footer: {
                Text(trs(Lang.names[min(max(store.lang, 0), Lang.count - 1)]))
            }
            // the app's own language (buttons, menus, explanations); the dictionaries stay as they are
            Section {
                Picker(tr("介面語言"), selection: $uiLang) {
                    Text(tr("中文")).tag(0)
                    Text("English").tag(1)
                }
                .pickerStyle(.segmented)
            } header: {
                Text(tr("介面語言"))
            } footer: {
                Text(tr("按鈕、選單和說明的語言。詞典的內容（意思、例句）不會變。"))
            }
            Section(tr("台語")) {
                Picker(tr("拼寫"), selection: $rom) {
                    ForEach(0..<ROM_NAMES.count, id: \.self) { Text(trs(ROM_NAMES[$0] == "方音" ? "只用方音" : ROM_NAMES[$0])).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(tr("腔口"), selection: $place) {
                    Text(tr("通行")).tag(-1)
                    ForEach(Array(PLACE_NAMES.enumerated()), id: \.offset) { i, p in Text(trs(p)).tag(i) }
                }
                .onChange(of: place) { if place >= 0 { store.loadDict() } }
            }
            Section {
                Picker(tr("字形"), selection: $simplified) {
                    Text(tr("正體字")).tag(false)
                    Text(tr("簡體字")).tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: simplified) { store.simplifiedChanged() }
            } header: {
                Text(tr("字形"))
            } footer: {
                Text(tr("華語和粵語的卡片、詞典和例句用哪一種字寫。台語一直用正體字；手寫練習也是正體字。"))
            }
            Section(tr("華語")) {
                Picker(tr("拼寫"), selection: $zhRomSaved) {
                    Text(trs("拼音")).tag(0)
                    Text(trs("注音")).tag(1)
                }
                .pickerStyle(.segmented)
                .onChange(of: zhRomSaved) { if store.lang == 1 { store.zhRom = zhRomSaved } }
                Picker(tr("讀音"), selection: $store.zhPlace) {
                    ForEach(0..<Lang.zhPlaceNames.count, id: \.self) { Text(trs(Lang.zhPlaceNames[$0])).tag($0) }
                }
                .pickerStyle(.segmented)
                if store.zhPlace == 2 {
                    Text(ZhDict.sichuanFile.isEmpty
                         ? tr("還沒有四川話的讀音資料：在 Mac 上重新執行一次安裝（會從維基詞典整理），之前先把 kaikki.org 的中文檔案放在「下載」裡會比較快。現在顯示普通話的讀音。")
                         : tr("成都話的讀音（維基詞典），用四川話拼音，聲調標在母音上，照聲調的聲音：1 陰平 ā 高平（紅）、2 陽平 a̱ 低降（青綠）、3 上聲 à 高降（紫）、4 去聲 ǎ 低降升（藍）。搜尋的時候聲調可以打數字（ngai4）。讀音的來源：沒有框是維基詞典的；粉紅色的框是照每個字在其他詞裡的讀音推算的；黃色的框是照普通話和四川話一般的語音對應預測的（比較常錯）；橘色的框是沒辦法推的詞，顯示普通話的標準讀音。詞典也查得到四川話自己的詞（標「四川話」，從維基詞典的方言對照表），查華語的詞會列出四川話的講法。發音和聲調練習還是普通話的。"))
                        .ffFont(.footnote).foregroundStyle(T.muted)
                }
                Picker(tr("詞表"), selection: $store.zhList) {
                    ForEach(0..<Lang.listNames.count, id: \.self) { Text(Lang.listNames[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker(tr("拼寫"), selection: $yueRomSaved) {
                    Text(trs("粵拼")).tag(0)
                    Text(trs("耶魯")).tag(1)
                }
                .pickerStyle(.segmented)
                .onChange(of: yueRomSaved) { if store.lang == 2 { store.zhRom = yueRomSaved } }
            } header: {
                Text(tr("粵語"))
            } footer: {
                Text(tr("粵拼（香港語言學學會）或耶魯拼音。詞是照常用的程度分組，每組 500 個。"))
            }
            Section {
                Picker(tr("拼寫"), selection: $hakRomSaved) {
                    Text(trs("拼音")).tag(0)
                    Text(trs("注音")).tag(1)
                }
                .pickerStyle(.segmented)
                .onChange(of: hakRomSaved) { if store.lang == 3 { store.zhRom = hakRomSaved } }
                Picker(tr("腔"), selection: $store.hakAccent) {
                    ForEach(0..<Lang.hakAccents.count, id: \.self) { Text(trs(Lang.hakAccents[$0])).tag($0) }
                }
            } header: {
                Text(tr("客語"))
            } footer: {
                Text(tr("臺灣客家語拼音（聲調記號照各腔），或客語注音。換腔的時候詞典會重新讀一次。詞是照在辭典例句裡出現的次數分組，每組 500 個。"))
            }
            Section {
                Picker(tr("拼寫"), selection: $jaRomSaved) {
                    Text(trs("假名")).tag(1)
                    Text(trs("羅馬字")).tag(0)
                }
                .pickerStyle(.segmented)
                .onChange(of: jaRomSaved) { if store.lang == 4 { store.zhRom = jaRomSaved } }
            } header: {
                Text(tr("日語"))
            } footer: {
                Text(tr("讀音用假名或羅馬字（平文式）。詞是 JMdict 標成常用的詞，照常用的程度分組，每組 500 個；漢字卡照報紙裡出現的次數排。"))
            }
            Section {
                Picker(tr("詞下面"), selection: $svRomSaved) {
                    Text(trs("詞素")).tag(0)
                    Text(trs("不顯示")).tag(1)
                }
                .pickerStyle(.segmented)
                .onChange(of: svRomSaved) { if store.lang == 5 { store.zhRom = svRomSaved } }
                Toggle(tr("沒有中文解釋的詞：由英文推測中文"), isOn: $svGuess)
            } header: {
                Text(tr("瑞典語"))
            } footer: {
                Text(tr("詞下面用連字號分開詞素（be-tal-a），每個部分一種顏色。詞是照字幕裡出現的次數分組，每組 500 個（FrequencyWords）。由英文推測的中文是照 CC-CEDICT 裡英文解釋相同的華語詞，標「由英文推測」，不一定準（要重新安裝一次瑞典語詞典才有）。"))
            }
        }
    }
}

// MARK: 卡片與練習

private struct PracticeSettings: View {
    @EnvironmentObject var store: Store
    @AppStorage("hideMeaning") private var hideMeaning = false
    @AppStorage(CardLook.hideReadingKey) private var hideReading = false
    @AppStorage(ZhMeaning.key) private var zhEnglish = false
    @AppStorage(HandInk.rainbowKey) private var rainbow = false
    @AppStorage(HandInk.colorKey) private var inkColor = 0
    @AppStorage(Kaiti.styleKey) private var handFont = 0
    @AppStorage("goal") private var goal = 3
    @AppStorage("sessionSize") private var sessionSize = 10
    @AppStorage(WordWrite.key) private var practiceWrite = true
    @State private var confirmReset = false

    var body: some View {
        SettingsPage(title: tr("卡片與練習")) {
            Section {
                Toggle(tr("卡片先隱藏意思"), isOn: $hideMeaning)
                Toggle(tr("卡片先隱藏讀音"), isOn: $hideReading)
                Stepper(tr("連續答對 \(goal) 次算學會"), value: $goal, in: 1...6)
                Stepper(tr("每次練習 \(sessionSize) 個詞"), value: $sessionSize, in: 5...40, step: 5)
                Toggle(tr("寫字題"), isOn: $practiceWrite)
            } footer: {
                Text(tr("開始練習和本週學習裡，看意思和讀音把整個詞寫出來，寫完自己對答案。"))
            }
            MainMeaningSection()
            Section {
                PenSettings()
                NavigationLink { InkColorPicker() } label: {
                    HStack {
                        Text(tr("筆的顏色"))
                        Spacer()
                        Text(rainbow ? trs("彩虹") : (inkColor == 0 ? trs("墨色") : trs("自己選的"))).foregroundStyle(T.muted)
                        InkSwatch(size: 18)
                    }
                }
                Picker(tr("字體"), selection: $handFont) {
                    ForEach(Kaiti.styles.indices, id: \.self) { Text(trs(Kaiti.styles[$0].name)).tag($0) }
                }
            } header: {
                Text(tr("手寫練習"))
            } footer: {
                Text(tr("筆：簽字筆怎麼按都一樣粗；原子筆、鋼筆用 Apple Pencil 按得越用力越粗（鋼筆變最多）；鉛筆、麥克筆、蠟筆、水彩像真的筆。粗細：筆的粗細。筆跡延遲：筆寫過去以後，等一下字才出現（0 = 馬上出現）。這些在手寫練習右上角的筆也可以改。筆的顏色：墨色（深色的墨水）、彩虹（每一筆換一個顏色，比較容易看出筆順）或自己選一個顏色（手寫練習右上角的顏色也可以改）。字體：上面的字和描字用的字，楷體（Apple 的，第一次要下載）、文楷（霞鶩文楷）或芫荽（照臺灣教育部的寫法）"))
            }
            Section {
                Button(tr("全部重來"), role: .destructive) { confirmReset = true }
            } footer: {
                Text(tr("所有的「熟悉」和「不熟」都清掉，從頭開始。"))
            }
        }
        .confirmationDialog(tr("所有的「熟悉」和「不熟」都會清掉，從頭開始。"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(tr("全部重來"), role: .destructive) { store.resetAll() }
        }
    }
}

// MARK: 詞典

private struct DictionarySettings: View {
    @AppStorage("wordGap") private var wordGap = true
    @AppStorage(SenseCopy.tplKey) private var copyTpl = SenseCopy.presets[0].tpl
    @AppStorage(SenseCopy.exKey) private var copyEx = SenseCopy.presets[0].ex
    @AppStorage(SenseCopy.sepKey) private var copySep = SenseCopy.presets[0].sep
    @AppStorage(SenseCopy.zhTplKey) private var zhCopyTpl = SenseCopy.zhPresets[0].tpl
    @AppStorage(SenseCopy.zhExKey) private var zhCopyEx = SenseCopy.zhPresets[0].ex
    @AppStorage(SenseCopy.zhSepKey) private var zhCopySep = SenseCopy.zhPresets[0].sep
    @AppStorage(ZhMeaning.key) private var zhEnglish = false

    var body: some View {
        SettingsPage(title: tr("詞典")) {
            Section {
                Toggle(tr("例句的詞分開一點"), isOn: $wordGap)
                let _ = copyTpl + copyEx + zhCopyTpl + zhCopyEx + "\(copySep)\(zhCopySep)"
                NavigationLink { SenseCopySettings(zh: false) } label: {
                    LabeledContent(trs("複製意思的格式（台語）"), value: SenseCopy.styleName(zh: false))
                }
                NavigationLink { SenseCopySettings(zh: true) } label: {
                    LabeledContent(trs("複製意思的格式（華語）"), value: SenseCopy.styleName(zh: true))
                }
            } footer: {
                Text(tr("台語和華語各有自己的複製格式。華語可以加英文解釋：{英文} 或 {英文列表}。"))
            }
            MainMeaningSection()
            InputCodesSettings()
        }
    }
}

// MARK: 聲音

private struct SoundSettings: View {
    @AppStorage("autoPlay") private var autoPlay = false
    @AppStorage("volume") private var volume = 0.8
    @AppStorage("audioBase") private var audioBase = Audio.defaultBase
    @State private var message: String?

    var body: some View {
        SettingsPage(title: tr("聲音")) {
            Section {
                Toggle(tr("新卡片自動播放發音"), isOn: $autoPlay)
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(T.muted)
                    Slider(value: $volume, in: 0...1, step: 0.05)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(T.muted)
                }
            }
            Section {
                TextField(tr("音檔來源"), text: $audioBase)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .clearButton($audioBase)
                    .ffFont(.footnote)
                Button(tr("清除已下載的音檔")) { Player.shared.clearCache(); message = "已清除。" }
            } header: {
                Text(tr("台語音檔"))
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(tr("好")) { message = nil }
        }
    }
}

// MARK: 備份與同步

private struct BackupSettings: View {
    @EnvironmentObject var store: Store
    @AppStorage("syncDevices") private var syncDevices = true
    @State private var picking = false
    @State private var message: String?

    var body: some View {
        SettingsPage(title: tr("備份與同步")) {
            Section {
                if let name = store.backupFolderName {
                    LabeledContent(trs("資料夾"), value: name)
                    if let d = store.lastBackup {
                        LabeledContent(trs("上次備份"), value: d.formatted(date: .abbreviated, time: .shortened))
                    }
                    Toggle(tr("跟其他裝置同步"), isOn: $syncDevices)
                    Button(tr("立即備份")) { message = store.syncNow() }
                    Button(tr("換資料夾")) { picking = true }
                    Button(tr("停止自動備份"), role: .destructive) { store.clearBackupFolder() }
                } else {
                    Button(tr("選擇備份資料夾…")) { picking = true }
                }
            } footer: {
                Text(tr("建議用 iCloud Drive。每台裝置選同一個資料夾，進度就會同步。"))
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType.folder]) { result in
            if case .success(let url) = result { message = store.setBackupFolder(url) }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(tr("好")) { message = nil }
        }
    }
}

// MARK: 匯出與匯入

private struct ExportSettings: View {
    @EnvironmentObject var store: Store
    @State private var shareItem: ShareItem?
    @State private var importing = false
    @State private var message: String?
    /// importing a backup: how far it is (nil = not importing)
    @State private var importProgress: Double?

    var body: some View {
        SettingsPage(title: tr("匯出與匯入")) {
            Section {
                Button(tr("匯出「不熟」CSV")) { share(Data(store.csv(store.unknownCards).utf8), "方方-不熟.csv") }
                Button(tr("匯出「熟悉」CSV")) { share(Data(store.csv(store.knownCards).utf8), "方方-熟悉.csv") }
            } footer: {
                Text(tr("跟方方網站的收藏格式一樣（分號分隔）。"))
            }
            Section {
                Button(tr("匯出到 Anki（不熟＋熟悉）")) {
                    let r = UserDefaults.standard.integer(forKey: "rom"), pl = UserDefaults.standard.object(forKey: "place") as? Int ?? -1
                    share(Data(store.ankiTSV(store.unknownCards + store.knownCards, rom: r, place: pl).utf8), "方方-Anki-\(Lang.names[store.lang]).txt")
                }
            } header: {
                Text(tr("Anki"))
            } footer: {
                Text(tr("在 Anki 選「檔案 → 匯入」，選這個檔案：正面是詞，背面是讀音、意思和一個例句（你自己存的句子優先）。會放進「方方詞卡::語言」牌組，標籤是「不熟」或「熟悉」。現在的語言的詞，拼寫和腔口照目前的設定。"))
            }
            Section {
                Button(tr("備份檔分享／另存")) { share(store.backupData(), "方方詞卡備份.json") }
                Button(tr("匯入備份／方方收藏")) { importing = true }
            } footer: {
                Text(tr("方方網站或擴充功能的收藏會加到「不熟」。"))
            }
        }
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType.json]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: url) else { message = trs("讀不到這個檔案。"); return }
            importProgress = 0
            Task {
                let m = await store.importBackup(d) { v in importProgress = v }
                // let the potion fill up before it goes
                try? await Task.sleep(nanoseconds: 450_000_000)
                importProgress = nil
                message = m
            }
        }
        .overlay {
            if let v = importProgress {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 12) {
                        Text(tr("匯入備份中…")).ffFont(.headline).foregroundStyle(T.glyph)
                        PotionBar(value: v, height: 28, showMarks: false, label: trs("匯入進度"))
                        Text("\(Int((v * 100).rounded()))%").latFont(15).monospacedDigit().foregroundStyle(T.muted)
                        Text(tr("資料很多的時候要等一下，請不要關掉 App。")).ffFont(.caption).foregroundStyle(T.muted)
                    }
                    .padding(22)
                    .frame(maxWidth: 360)
                    .background(RoundedRectangle(cornerRadius: 22).fill(T.fn))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(T.fnEdge, lineWidth: 1.5))
                    .padding(30)
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: importProgress == nil)
        .interactiveDismissDisabled(importProgress != nil)
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(tr("好")) { message = nil }
        }
    }

    private func share(_ data: Data, _ name: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch {
            message = trs("匯出失敗。")
        }
    }
}

// MARK: 關於與資料來源

private struct AboutSettings: View {
    var body: some View {
        SettingsPage(title: tr("關於與資料來源")) {
            Section(tr("台語")) {
                credit(tr("詞條、讀音、釋義、例句、音檔"), "教育部《臺灣台語常用詞辭典》（CC BY-ND 3.0 臺灣）。釋義、例句原文照錄，音檔未經修改；讀音依規則轉成皓羅、方音、白話字。")
                credit(tr("推算的內容"), "辭典沒寫的腔口讀音是依規則推算的，用紅色和「推測」標示。")
                credit(tr("音節編碼"), "YuRen-tw《rime-taigi-tps》（經作者同意使用）")
                if let c = TaigiSpeechInfo.credit { credit(tr("轉換的朗讀"), c) }
                credit(tr("皓羅、自補詞條"), "Unoki99")
                credit(tr("皓羅字型"), "DejaVu Sans")
                credit(tr("手寫練習的字體"), "文楷：霞鶩文楷 TC（LXGW）；芫荽：Iansui（The Iansui Project Authors）。都是 SIL Open Font License 1.1。楷體：Apple 的華文楷體。")
                credit(tr("詞頻"), "教育部辭典例句、Rime《八股文》（LGPL-3.0）")
                credit(tr("英文解釋"), "維基詞典（Wiktionary，經 kaikki.org wiktextract 整理，CC BY-SA 4.0）：漢字一樣、閩南語讀音也一樣的詞。另外存，不改辭典的內容。")
            }
            Section(tr("華語")) {
                credit(tr("詞條、注音、釋義、例句"), "中華文化總會《兩岸常用詞典》（CC BY-NC-ND），g0v 萌典整理。拼音依注音轉寫，例句讀音依詞推算。")
                credit(tr("漢字卡的字義"), "教育部《重編國語辭典修訂本》（創用CC 姓名標示-禁止改作 3.0 臺灣），g0v 萌典整理。解釋和用例照錄，引用的古書省略。")
                credit(tr("漢字等級"), "HSK 3.0 漢字表、TOCFL（TBCL）漢字表")
                credit(tr("英文解釋"), "CC-CEDICT（CC BY-SA 4.0）")
                credit(tr("詞表"), "HSK 3.0（ivankra/hsk30，MIT）、TOCFL 華語八千詞（ivankra/tocfl）")
                credit(tr("部首組合"), "字的組成：cjkvi-ids（CHISE IDS，GPLv2）")
                credit(tr("四川話讀音"), "維基詞典（Wiktionary，經 kaikki.org wiktextract 整理，CC BY-SA 4.0）：成都話的四川話拼音，漢字一樣、普通話讀音也一樣的詞。另外存，不改辭典的內容。")
                credit(tr("發音"), "裝置內建的語音")
            }
            Section(tr("練習")) {
                credit(tr("複習的間隔"), "照 SM-2 的方法自己寫的：Algorithm SM-2, (C) Copyright SuperMemo World, 1991. www.supermemo.com")
            }
            Section(tr("粵語")) {
                credit(tr("詞條、粵拼、英文解釋"), "CC-Canto（Pleco，CC BY-SA 3.0）、CC-CEDICT（CC BY-SA 4.0）")
                credit(tr("意思、例句、華語對照、錄音"), "維基詞典（Wiktionary，經 kaikki.org wiktextract 整理，CC BY-SA 4.0）；錄音來自 Wikimedia Commons")
                credit(tr("讀音、詞頻"), "rime-cantonese（CC BY 4.0／ODbL）")
                credit(tr("漢字卡的字義"), "開放詞典《開放粵語字典》（kfcd/yyzd，CC BY 3.0）")
                credit(tr("發音"), "有錄音的詞用錄音，其他用裝置內建的語音")
            }
            Section(tr("客語")) {
                credit(tr("詞條、六腔讀音、意思、例句"), "教育部《臺灣客語辭典》（創用CC 姓名標示-禁止改作 3.0 臺灣）。資料在自己的電腦上下載、整理，不另外散布。")
                credit(tr("英文解釋"), "CC-CEDICT（CC BY-SA 4.0）：華語寫法相同的詞的英文解釋，客語的意思可能不完全一樣")
                credit(tr("注音"), "照臺灣客家語拼音方案由拼音轉寫")
            }
            Section(tr("其他")) {
                credit(tr("輸入法拆碼"), "倉頡、五筆：Rime 碼表（LGPL-3.0）")
                Text(tr("本 App 與教育部無關，不是官方產品。")).ffFont(.footnote).foregroundStyle(T.muted)
            }
        }
    }

    private func credit(_ what: String, _ who: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(what).ffFont(.caption).foregroundStyle(T.muted)
            Text(who).ffFont(.footnote)
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: Safari 查詞

/// Safari 查詞: how to turn it on and use it (its own settings are in the card, under 設定)
private struct SafariLookupSection: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    var body: some View {
        Section {
            // the words you know, to Safari 查詞 (it marks the new ones in subtitles and shows 懂 %)
            Button {
                if let p = SafariKnownSync.payload(store) { openURL(p.url) }
            } label: {
                Label(tr("把認識的詞傳到 Safari 查詞"), systemImage: "arrow.up.forward.app")
            }
            Text(tr("在 Safari 用 Apple Pencil 停在一個中文字上面（不要碰到螢幕），就會跳出那個詞的華語和台語解釋。沒有懸停功能的 iPad 可以用手指選取一個詞，觸控板的游標也可以。卡片右上角的「設定」可以選拼寫、腔口、聲調顏色和要顯示的語言。按「加到不熟」或「收藏」選好詞以後，按「傳到 App」就會打開方方詞卡把詞加進來。"))
                .ffFont(.footnote).foregroundStyle(T.muted)
            if SafariImport.waitingCount > 0 {
                Text(tr("有 \(SafariImport.waitingCount) 個從 Safari 傳來的詞在等：切到它們的語言（華語或台語）就會加進不熟。"))
                    .ffFont(.footnote).foregroundStyle(T.oliveInk)
            }
        } header: {
            Text(tr("Safari 查詞"))
        } footer: {
Text(tr("開啟：設定 → App → Safari → 延伸功能 → 方方詞卡 查詞，打開並允許「所有網站」。查詞的資料在安裝的時候放進延伸功能裡，所以重新執行安裝以後才會有新的詞。「把認識的詞傳到 Safari 查詞」會在 Safari 打開 example.com，詞放在網址的 # 後面，不會傳到網路上；之後影片字幕裡沒學過的詞會有底線，面板上會顯示你懂多少。學了新詞以後可以再傳一次。"))
        }
    }
}


/// 設定 → 主要解釋: for each language that has both, the 華語 meaning or the English one on the cards, in practice and
/// in the lists (粵語's meanings are English already). Opening a word shows both.
struct MainMeaningSection: View {
    @AppStorage(ZhMeaning.twKey) private var tw = false
    @AppStorage(ZhMeaning.key) private var zh = false
    @AppStorage(ZhMeaning.hakKey) private var hak = false
    var body: some View {
        Section {
            row(trs("台語"), $tw)
            row(trs("華語"), $zh)
            row(trs("客語"), $hak)
        } header: {
            Text(tr("主要解釋"))
        } footer: {
            Text(tr("卡片、練習和查詞列表上先顯示哪一種解釋。點進一個詞以後兩種都看得到。台語的英文解釋來自維基詞典，不是每個詞都有；沒有的話顯示華語的。"))
        }
    }
    private func row(_ name: String, _ v: Binding<Bool>) -> some View {
        Picker(name, selection: v) {
            Text(tr("華語")).tag(false)
            Text(tr("英文")).tag(true)
        }
    }
}
