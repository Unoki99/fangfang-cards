import SwiftUI
import UIKit
import CoreText
import AVFoundation

@main
struct FangfangCardsApp: App {
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppTheme.key) private var theme = AppTheme.night.rawValue

    init() {
        // 日語 is read in kana until rōmaji is chosen
        UserDefaults.standard.register(defaults: [Lang.jaRomKey: 1])
        // 皓羅 font (DejaVu Sans subset) so tone marks sit right
        if let url = Bundle.main.url(forResource: "Haolo", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        // play audio even when the phone is on silent
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    var body: some Scene {
        WindowGroup {
            // the theme's colours are read while drawing: set it first, then draw everything again
            let _ = AppTheme.sync(theme)
            RootView()
                .id(theme)
                // (above the .id: 設定 stays open when the theme, the language or 介面語言 changes)
                .modifier(SettingsSheet())
                .fontDesign((AppTheme(rawValue: theme) ?? .night).fontDesign)
                .onAppear { MacWindow.setUp() }
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
                .macTextSize()
                // Safari 查詞's 傳到 App: the words chosen there
                .onOpenURL { url in SafariImport.handle(url, store) }
                .onChange(of: store.loaded) { SafariImport.apply(store) }
                // (a word of the other language: once its dictionary is open)
                .onChange(of: store.cards.count) { SafariImport.apply(store) }
        }
        .commands { TextSizeCommands() }
        .onChange(of: scenePhase) { _, phase in
            // pull changes from the other device when the app opens, back up when it closes
            if phase == .active { store.syncNow(); WidgetBridge.appOpened(store); SafariImport.apply(store) }
            else if phase == .background { store.saveNow(); store.syncNow(); WidgetBridge.flush(store) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var router = Router.shared
    @AppStorage("place") private var place = -1
    @AppStorage("rom") private var rom = 0
    @AppStorage(ToneColors.key) private var toneSys = 0
    @AppStorage(ToneColors.marksKey) private var toneMarks = false
    @AppStorage(ZhMeaning.key) private var zhEnglish = false
    @AppStorage("pickedLanguage") private var pickedLanguage = false
    @AppStorage(UILang.key) private var uiLang = 0
    /// (someone who used the app before this question was added: not asked)
    private var alreadyUsed: Bool {
        UserDefaults.standard.object(forKey: Lang.key) != nil || store.seenCount > 0
    }

    private var tabs: some View {
        TabView(selection: $router.tab) {
            NavigationStack { NewDeckView() }
                .tabItem { Label(tr("新詞"), systemImage: "rectangle.stack") }.tag(0)
            NavigationStack { UnknownView().rootPage(tr("不熟")) }
                .tabItem { Label(tr("不熟"), systemImage: "questionmark.circle") }.tag(1)
            NavigationStack { DictionaryView().rootPage(tr("詞典")) }
                .tabItem { Label(tr("詞典"), systemImage: "character.book.closed") }.tag(4)
            NavigationStack { KnownView().rootPage(tr("熟悉")) }
                .tabItem { Label(tr("熟悉"), systemImage: "checkmark.circle") }.tag(2)
            NavigationStack { ConverterView().rootPage(tr("轉換")) }
                .tabItem { Label(tr("轉換"), systemImage: "arrow.left.arrow.right") }.tag(3)
        }
    }

    var body: some View {
        Group {
            if store.loaded {
                if #available(iOS 18.0, *) {
                    // iPad and Mac: the tabs can become a sidebar
                    TabView(selection: $router.tab) {
                        // order: 新詞 不熟 詞典 熟悉 轉換 (the values stay the same for Shortcuts)
                        Tab(tr("新詞"), systemImage: "rectangle.stack", value: 0) { NavigationStack { NewDeckView() } }
                        Tab(tr("不熟"), systemImage: "questionmark.circle", value: 1) { NavigationStack { UnknownView().rootPage(tr("不熟")) } }
                        Tab(tr("詞典"), systemImage: "character.book.closed", value: 4) { NavigationStack { DictionaryView().rootPage(tr("詞典")) } }
                        Tab(tr("熟悉"), systemImage: "checkmark.circle", value: 2) { NavigationStack { KnownView().rootPage(tr("熟悉")) } }
                        Tab(tr("轉換"), systemImage: "arrow.left.arrow.right", value: 3) { NavigationStack { ConverterView().rootPage(tr("轉換")) } }
                    }
                    .tabViewStyle(.sidebarAdaptable)
                    .id("\(store.lang)\(uiLang)")          // 台語 ⇄ 華語 (or 介面語言): every page starts again
                } else {
                    tabs.id("\(store.lang)\(uiLang)")
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(store.loadError ?? trs("載入字典…")).foregroundStyle(T.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackground()
                .task {
                    store.load()
                    // 詞典的字體 = 楷體: Apple's downloaded font is made usable again (it's kept, but asked for each time)
                    if DictFont.chosen == 1 { Kaiti.prepare { _ in } }
                }
            }
        }
        // the very first time: which language to learn (later: 設定 → 語言)
        .fullScreenCover(isPresented: Binding(get: { store.loaded && !pickedLanguage && !alreadyUsed },
                                              set: { if !$0 { pickedLanguage = true } })) {
            LanguageWelcome { l in
                store.setLanguage(l)
                pickedLanguage = true
            }
            .environmentObject(store)
        }
        .overlay {
            // no 台語 data yet: install it here
            if store.loaded && store.lang == 0 && store.taigiMissing {
                ZStack {
                    T.bg.opacity(0.85).ignoresSafeArea()
                    MissingDictView(lang: 0)
                }
            }
        }
        .overlay {
            // loading the 華語 dictionary (the first time 華語 is chosen)
            if store.switching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(tr("載入\(trs(Lang.names[max(Lang.current, 1)]))詞典…")).ffFont(.subheadline).foregroundStyle(T.glyph)
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 18).fill(T.fn.opacity(0.95)))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(T.fnEdge, lineWidth: 1.5))
            }
        }
        .alert(tr("粵語的語音"), isPresented: Binding(get: { store.speechHint != nil }, set: { if !$0 { store.speechHint = nil } })) {
            Button(tr("好")) { store.speechHint = nil }
        } message: { Text(store.speechHint ?? "") }
        .alert(tr("\(trs(Lang.names[max(Lang.current, 1)]))詞典"), isPresented: Binding(get: { store.zhError != nil }, set: { if !$0 { store.clearZhError() } })) {
            Button(tr("好")) { store.clearZhError() }
        } message: { Text(store.zhError ?? "") }
        // a place chosen anywhere: load the dictionary (guessed readings, example sentences)
        .onChange(of: place) {
            if place >= 0 { store.loadDict() }
            WidgetBridge.writeState(store); WidgetBridge.rebuildIfNeeded(store)
        }
        // the 分類 widgets: new spelling, the word list once loaded, local readings once the dictionary is there
        .onChange(of: rom) { if rom == 3 { store.loadDict() }; WidgetBridge.writeState(store) }
        // 聲調顏色 needs the dictionary (word classes, readings in sentences)
        .onChange(of: toneSys) { if toneSys != 0 { store.loadDict() }; WidgetBridge.rebuildIfNeeded(store) }
        .onChange(of: toneMarks) { WidgetBridge.rebuildIfNeeded(store) }
        // 華語 words on the widgets: their meaning, reading and word list
        .onChange(of: zhEnglish) { WidgetBridge.writeState(store); WidgetBridge.rebuildIfNeeded(store) }
        .onChange(of: store.zhList) { WidgetBridge.rebuildIfNeeded(store) }
        .onChange(of: store.zhRom) { WidgetBridge.writeState(store); WidgetBridge.rebuildIfNeeded(store) }
        .onChange(of: store.zhPlace) { WidgetBridge.writeState(store); WidgetBridge.rebuildIfNeeded(store) }
        .onChange(of: store.loaded) { WidgetBridge.appOpened(store) }
        .onChange(of: store.dict != nil) { WidgetBridge.rebuildIfNeeded(store) }
    }
}

/// ⚙︎ in the top bar of every tab opens 設定 (the tab bar has room for five tabs)
struct SettingsButton: View {
    var body: some View {
        Button { Router.shared.settingsOpen = true } label: { Image(systemName: "gearshape").foregroundStyle(T.glyph) }
            .accessibilityLabel(tr("設定"))
    }
}

/// 設定, opened by ⚙︎. It's shown from the app itself, not from the page the ⚙︎ is on: changing the language,
/// 介面語言 or the theme draws every page again, and a sheet of one of those pages would close with it.
struct SettingsSheet: ViewModifier {
    @ObservedObject private var router = Router.shared
    @AppStorage(UILang.key) private var uiLang = 0
    @AppStorage(AppTheme.key) private var theme = AppTheme.night.rawValue
    func body(content: Content) -> some View {
        content.sheet(isPresented: $router.settingsOpen) {
            NavigationStack {
                SettingsView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("完成")) { router.settingsOpen = false } } }
            }
            .environmentObject(Store.shared)
            .macTextSize()
            .fontDesign((AppTheme(rawValue: theme) ?? .night).fontDesign)
            .preferredColorScheme(.dark)
            .tint(AppTint.accent)
        }
    }
}

extension View {
    func settingsButton() -> some View {
        toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
    }

    /// a main page (tab): its name isn't shown (the tab bar shows it; it's still the back button's label).
    /// At the right, always in this order: the page's own buttons, spelling / 腔口 / 調, ⚙︎ last.
    func rootPage(_ title: String) -> some View { modifier(RootPageBar(title: title, extra: EmptyView())) }
    func rootPage<E: View>(_ title: String, @ViewBuilder extra: () -> E) -> some View {
        modifier(RootPageBar(title: title, extra: extra()))
    }
}

struct RootPageBar<Extra: View>: ViewModifier {
    let title: String
    let extra: Extra
    @Environment(\.horizontalSizeClass) private var hsc
    /// an iPad (not the Mac, where the window's toolbar has room)
    private var onPad: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
    /// the iPhone / iPad app running on a Mac (Apple silicon): the window's toolbar drops items that don't fit,
    /// so ⚙︎ gets an item of its own, the first one kept
    private var iPadAppOnMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac }
    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("") }
                if iPadAppOnMac {
                    ToolbarItem(placement: .topBarLeading) { extra.fixedSize() }
                    ToolbarItem(placement: .primaryAction) { SettingsButton() }
                    ToolbarItem(placement: .topBarTrailing) { CompactReadingMenu().fixedSize() }
                } else if hsc == .compact || onPad {
                    // a narrow top bar (iPhone held upright), or an iPad (its tabs float in the middle of the top
                    // bar): the page's own button (新詞's group) on the left, the spelling, language and tone colours
                    // in one menu on the right
                    ToolbarItem(placement: .topBarLeading) { extra.fixedSize() }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 10) {
                            CompactReadingMenu()
                            SettingsButton()
                        }
                        .fixedSize()
                    }
                } else {
                    // one item, at its full width: as separate items, the ones that didn't fit were dropped
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 10) {
                            extra
                            RomButton()
                            SettingsButton()
                        }
                        .fixedSize()
                    }
                }
            }
    }
}

/// Mac: a sensible starting and minimum window size
enum MacWindow {
    /// Mac: every window uses the chosen text size (設定 → 文字大小)
    @MainActor static func applyTextSize(_ level: Int) {
        #if targetEnvironment(macCatalyst)
        let size = UIContentSizeCategory(TextSize.levels[TextSize.clamp(level)])
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.traitOverrides.preferredContentSizeCategory = size
        }
        #endif
    }

    @MainActor static func setUp() {
        #if targetEnvironment(macCatalyst)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = CGSize(width: 720, height: 620)
            scene.sizeRestrictions?.maximumSize = CGSize(width: 10000, height: 10000)
            scene.title = "方方詞卡"
        }
        #endif
    }
}

enum AppTint {
    /// light green on iPhone/iPad; on the Mac the system fills active buttons with the accent colour,
    /// so it's the darker green there (light text stays readable)
    #if targetEnvironment(macCatalyst)
    static var accent: Color { T.btnEdge }
    #else
    static var accent: Color { T.btnInk }
    #endif
}

/// the very first time the app opens: 台語, 華語 or 粵語 (can be changed any time in 設定 → 語言)
struct LanguageWelcome: View {
    let pick: (Int) -> Void
    /// the app's own language (介面語言), chosen here too
    @AppStorage(UILang.key) private var uiLang = 0
    /// 0: the app's language, the meanings and the spellings; 1: which language to learn first
    @State private var step = 0
    @AppStorage(ZhMeaning.key) private var zhEnglish = false
    @AppStorage(ZhMeaning.twKey) private var twEnglish = false
    @AppStorage(ZhMeaning.hakKey) private var hakEnglish = false
    @AppStorage("rom") private var twRom = 0
    @AppStorage("zhRom") private var zhRom = 0
    @AppStorage(Lang.yueRomKey) private var yueRom = 0
    @AppStorage(Lang.hakRomKey) private var hakRom = 0
    @AppStorage(Lang.jaRomKey) private var jaRom = 1
    /// the language chosen, its dictionary being downloaded and made (nothing is in the app until then)
    @State private var installing: Int?
    @ObservedObject private var installer = DictInstaller.shared

    var body: some View {
        if let l = installing { install(l) } else if step == 0 { setup } else { languages }
    }

    /// the language's dictionary is there already: straight on; otherwise it's downloaded and made first
    private func choose(_ l: Int) {
        guard let p = DictPack.of(lang: l), let main = p.outputs.first, !DataFiles.has(main) else { pick(l); return }
        installing = l
        if case .working = installer.state(p) { return }
        installer.install(p)
    }

    /// downloading and making the dictionary of the language chosen
    private func install(_ l: Int) -> some View {
        let p = DictPack.of(lang: l)
        let c = T.langColors(l)
        return VStack(spacing: 22) {
            Spacer(minLength: 0)
            Text(["台", "華", "粵", "客", "日"][min(max(l, 0), 4)]).scaledFont(54, weight: .bold).foregroundStyle(c.ink)
                .frame(width: 96, height: 96)
                .background(Circle().fill(c.edge.opacity(0.35)))
            Text(tr("安裝\(trs(Lang.names[l]))詞典")).ffFont(.title2, .bold).foregroundStyle(T.glyph)
            if let p {
                Text(trs(p.from) + "\n" + trs(p.download)).ffFont(.footnote).foregroundStyle(T.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: 460)
                switch installer.state(p) {
                case .working(let f, let t):
                    ProgressView(value: f).tint(c.edge).frame(maxWidth: 320)
                    Text(t).ffFont(.footnote).foregroundStyle(T.muted)
                    Text(tr("要網路，大概一兩分鐘。請讓 App 開著。")).ffFont(.caption).foregroundStyle(T.muted)
                        .multilineTextAlignment(.center)
                case .failed(let m):
                    Text(m).ffFont(.footnote).foregroundStyle(ToneColors.red).multilineTextAlignment(.center).frame(maxWidth: 460)
                    Button { installer.install(p) } label: { Text(tr("再試一次")).ffFont(.headline).frame(maxWidth: 260, minHeight: 30) }
                        .prominentButton(c.edge)
                case .idle:
                    if DataFiles.has(p.outputs.first ?? "") {
                        ProgressView().onAppear { pick(l) }
                    } else {
                        Button { installer.install(p) } label: { Text(tr("下載並安裝")).ffFont(.headline).frame(maxWidth: 260, minHeight: 30) }
                            .prominentButton(c.edge)
                    }
                }
            }
            HStack(spacing: 18) {
                Button { installing = nil } label: { Label(tr("換一種語言"), systemImage: "chevron.left") }
                Button { pick(l) } label: { Text(tr("先不要，進入 App")) }
            }
            .ffFont(.subheadline).foregroundStyle(T.muted)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .interactiveDismissDisabled()
        // made: into the app, in that language
        .onChange(of: installer.version) { if let p, DataFiles.has(p.outputs.first ?? "") { pick(l) } }
    }

    /// the app's language, then the meanings (華語 or English) and each language's spelling
    private var setup: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Text(tr("方方詞卡")).ffFont(.largeTitle, .bold).foregroundStyle(T.glyph)
                    Picker("", selection: $uiLang) {
                        Text("中文").tag(0)
                        Text("English").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("解釋先用哪一種語言？")).ffFont(.headline).foregroundStyle(T.glyph)
                        Picker("", selection: Binding(get: { zhEnglish }, set: { zhEnglish = $0; twEnglish = $0; hakEnglish = $0 })) {
                            Text(tr("華語")).tag(false)
                            Text(tr("英文")).tag(true)
                        }
                        .pickerStyle(.segmented)
                        Text(tr("卡片和列表上先顯示的解釋（粵語的解釋是英文）。點進一個詞兩種都看得到。之後每個語言可以在「設定 → 詞典 → 主要解釋」分開改。"))
                            .ffFont(.caption).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("每個語言用哪一種拼寫？")).ffFont(.headline).foregroundStyle(T.glyph)
                        spelling(0, $twRom, ["皓羅", "台羅", "白話字", "方音"])
                        spelling(1, $zhRom, ["拼音", "注音"])
                        spelling(2, $yueRom, ["粵拼", "耶魯"])
                        spelling(3, $hakRom, ["拼音", "注音"])
                        spelling(4, $jaRom, ["羅馬字", "假名"])
                        Text(tr("台語選「方音」的話只顯示方音；其他的下面會再加一行方音。"))
                            .ffFont(.caption).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 22).fill(T.fn.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(T.fnEdge, lineWidth: 1.5))
                .frame(maxWidth: 520)
                Button { withAnimation(.snappy) { step = 1 } } label: {
                    Text(tr("下一步")).ffFont(.headline).frame(maxWidth: 260, minHeight: 30)
                }
                .prominentButton(T.blueEdge)
            }
            .id(uiLang)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .interactiveDismissDisabled()
    }

    private func spelling(_ l: Int, _ v: Binding<Int>, _ names: [String]) -> some View {
        let ink = [T.twInk, T.blueInk, T.oliveInk, T.hakInk, T.jaInk][l]
        return HStack(spacing: 10) {
            Text(trs(Lang.names[l])).ffFont(.subheadline, .bold).foregroundStyle(ink).frame(width: 64, alignment: .leading)
            Picker(trs(Lang.names[l]), selection: v) {
                ForEach(names.indices, id: \.self) { Text(trs(names[$0])).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var languages: some View {
        ScrollView {
        VStack(spacing: 24) {
            HStack {
                Button { withAnimation(.snappy) { step = 0 } } label: { Label(tr("上一步"), systemImage: "chevron.left") }
                    .foregroundStyle(T.muted)
                Spacer()
            }
            .frame(maxWidth: 520)
            VStack(spacing: 10) {
                Text(tr("方方詞卡")).ffFont(.largeTitle, .bold).foregroundStyle(T.glyph)
                Text(tr("你想先學哪一種？")).ffFont(.title3).foregroundStyle(T.muted)
            }
            .id(uiLang)
            VStack(spacing: 16) {
                choice(0, title: "台語", sub: "Taiwanese", note: tr("教育部《臺灣台語常用詞辭典》的詞，皓羅、台羅、白話字或方音"))
                choice(1, title: "華語", sub: "Mandarin", note: tr("《兩岸常用詞典》的詞，HSK／TOCFL，拼音或注音"))
                choice(2, title: "粵語", sub: "Cantonese", note: tr("CC-Canto、CC-CEDICT 和 rime-cantonese 的詞，粵拼或耶魯拼音"))
                choice(3, title: "客語", sub: "Hakka", note: tr("教育部《臺灣客語辭典》的詞，六個腔，拼音或注音"))
                choice(4, title: "日語", sub: "Japanese", note: tr("JMdict 和 KANJIDIC2 的詞和漢字，假名或羅馬字"))
            }
            .id(uiLang)
            .frame(maxWidth: 520)
            Text(tr("選了以後會下載那個語言的詞典，在這台裝置上整理好（App 裡面沒有內建詞典）。之後可以在「設定 → 語言與讀音」換，其他語言的詞典在「設定 → 詞典資料」安裝。")).id(uiLang)
                .multilineTextAlignment(.center)
                .ffFont(.footnote).foregroundStyle(T.muted)
                .frame(maxWidth: 520)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        }
        .appBackground()
        .interactiveDismissDisabled()
    }

    private func choice(_ l: Int, title: String, sub: String, note: String) -> some View {
        let fill = [T.twFill, T.blue, T.olive, T.hakFill, T.jaFill][l], edge = [T.twEdge, T.blueEdge, T.oliveEdge, T.hakEdge, T.jaEdge][l], ink = [T.twInk, T.blueInk, T.oliveInk, T.hakInk, T.jaInk][l]
        return Button { choose(l) } label: {
            HStack(spacing: 18) {
                Text(["台", "華", "粵", "客", "日"][l]).scaledFont(44, weight: .bold).foregroundStyle(ink)
                    .frame(width: 70, height: 70)
                    .background(Circle().fill(edge.opacity(0.35)))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title).ffFont(.title2, .bold).foregroundStyle(ink)
                        Text(sub).ffFont(.subheadline).foregroundStyle(ink.opacity(0.8))
                    }
                    Text(note).ffFont(.footnote).foregroundStyle(T.glyph.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(ink.opacity(0.7))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(edge, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(SwellButtonStyle())
    }
}
