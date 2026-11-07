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
                .fontDesign((AppTheme(rawValue: theme) ?? .night).fontDesign)
                .onAppear { MacWindow.setUp() }
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
                .macTextSize()
        }
        .commands { TextSizeCommands() }
        .onChange(of: scenePhase) { _, phase in
            // pull changes from the other device when the app opens, back up when it closes
            if phase == .active { store.syncNow(); WidgetBridge.appOpened(store) }
            else if phase == .background { store.saveNow(); store.syncNow() }
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
    /// (someone who used the app before this question was added: not asked)
    private var alreadyUsed: Bool {
        UserDefaults.standard.object(forKey: Lang.key) != nil || store.seenCount > 0
    }

    private var tabs: some View {
        TabView(selection: $router.tab) {
            NavigationStack { NewDeckView() }
                .tabItem { Label("新詞", systemImage: "rectangle.stack") }.tag(0)
            NavigationStack { UnknownView().rootPage("不熟") }
                .tabItem { Label("不熟", systemImage: "questionmark.circle") }.tag(1)
            NavigationStack { DictionaryView().rootPage("詞典") }
                .tabItem { Label("詞典", systemImage: "character.book.closed") }.tag(4)
            NavigationStack { KnownView().rootPage("熟悉") }
                .tabItem { Label("熟悉", systemImage: "checkmark.circle") }.tag(2)
            NavigationStack { ConverterView().rootPage("轉換") }
                .tabItem { Label("轉換", systemImage: "arrow.left.arrow.right") }.tag(3)
        }
    }

    var body: some View {
        Group {
            if store.loaded {
                if #available(iOS 18.0, *) {
                    // iPad and Mac: the tabs can become a sidebar
                    TabView(selection: $router.tab) {
                        // order: 新詞 不熟 詞典 熟悉 轉換 (the values stay the same for Shortcuts)
                        Tab("新詞", systemImage: "rectangle.stack", value: 0) { NavigationStack { NewDeckView() } }
                        Tab("不熟", systemImage: "questionmark.circle", value: 1) { NavigationStack { UnknownView().rootPage("不熟") } }
                        Tab("詞典", systemImage: "character.book.closed", value: 4) { NavigationStack { DictionaryView().rootPage("詞典") } }
                        Tab("熟悉", systemImage: "checkmark.circle", value: 2) { NavigationStack { KnownView().rootPage("熟悉") } }
                        Tab("轉換", systemImage: "arrow.left.arrow.right", value: 3) { NavigationStack { ConverterView().rootPage("轉換") } }
                    }
                    .tabViewStyle(.sidebarAdaptable)
                    .id(store.isZh)          // 台語 ⇄ 華語: every page starts again with the other deck
                } else {
                    tabs.id(store.isZh)
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(store.loadError ?? "載入字典…").foregroundStyle(T.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackground()
                .task { store.load() }
            }
        }
        // the very first time: which language to learn (later: 設定 → 語言)
        .fullScreenCover(isPresented: Binding(get: { store.loaded && !pickedLanguage && !alreadyUsed },
                                              set: { if !$0 { pickedLanguage = true } })) {
            LanguageWelcome { zh in
                store.setLanguage(zh: zh)
                pickedLanguage = true
            }
            .environmentObject(store)
        }
        .overlay {
            // loading the 華語 dictionary (the first time 華語 is chosen)
            if store.switching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("載入華語詞典…").ffFont(.subheadline).foregroundStyle(T.glyph)
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 18).fill(T.fn.opacity(0.95)))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(T.fnEdge, lineWidth: 1.5))
            }
        }
        .alert("華語詞典", isPresented: Binding(get: { store.zhError != nil }, set: { if !$0 { store.clearZhError() } })) {
            Button("好") { store.clearZhError() }
        } message: { Text(store.zhError ?? "") }
        // a place chosen anywhere: load the dictionary (guessed readings, example sentences)
        .onChange(of: place) {
            if place >= 0 { store.loadDict() }
            WidgetBridge.writeState(store); WidgetBridge.rebuildIfNeeded(store)
        }
        // the 分類 widgets: new spelling, the word list once loaded, local readings once the dictionary is there
        .onChange(of: rom) { WidgetBridge.writeState(store) }
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
    @EnvironmentObject var store: Store
    @State private var show = false
    var body: some View {
        Button { show = true } label: { Image(systemName: "gearshape").foregroundStyle(T.glyph) }
            .accessibilityLabel("設定")
            .sheet(isPresented: $show) {
                NavigationStack {
                    SettingsView()
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { show = false } } }
                }
                .environmentObject(store)
                .macTextSize()
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
    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("") }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    extra
                    RomButton()
                    SettingsButton()
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

/// the very first time the app opens: 台語 or 華語 (can be changed any time in 設定 → 語言)
struct LanguageWelcome: View {
    let pick: (Bool) -> Void
    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Text("方方詞卡").ffFont(.largeTitle, .bold).foregroundStyle(T.glyph)
                Text("你想先學哪一種？").ffFont(.title3).foregroundStyle(T.muted)
                Text("Which language would you like to start with?").ffFont(.subheadline).foregroundStyle(T.muted)
            }
            VStack(spacing: 16) {
                choice(zh: false, title: "台語", sub: "Taiwanese", note: "教育部《臺灣台語常用詞辭典》的詞，皓羅、台羅、白話字或方音")
                choice(zh: true, title: "華語", sub: "Mandarin", note: "《兩岸常用詞典》的詞，HSK／TOCFL，拼音或注音")
            }
            .frame(maxWidth: 520)
            Text("之後可以在「設定 → 語言」換。\nYou can change this later in Settings.")
                .multilineTextAlignment(.center)
                .ffFont(.footnote).foregroundStyle(T.muted)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .interactiveDismissDisabled()
    }

    private func choice(zh: Bool, title: String, sub: String, note: String) -> some View {
        let fill = zh ? T.blue : T.own, edge = zh ? T.blueEdge : T.ownEdge, ink = zh ? T.blueInk : T.purpleInk
        return Button { pick(zh) } label: {
            HStack(spacing: 18) {
                Text(zh ? "華" : "台").scaledFont(44, weight: .bold).foregroundStyle(ink)
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
