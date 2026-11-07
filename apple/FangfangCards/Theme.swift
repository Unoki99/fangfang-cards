import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

/// 主題 (設定 → 顯示 → 主題): 方方之夜 is the original look; 女巫小屋 a candle-lit witch's cottage; 星空 deep space;
/// 苔蘚小窩 goblincore (moss, mushrooms, pebbles and little treasures); 雪夜 a snowy winter night. The tone colours stay the same in all of them.
enum AppTheme: String, CaseIterable {
    case night, witch, space, goblin, winter
    static let key = "appTheme"
    /// read once per change (set from the app's root view), not on every colour lookup
    nonisolated(unsafe) static var current: AppTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .night
    var name: String {
        switch self {
        case .night: return trs("方方之夜")
        case .witch: return trs("女巫小屋")
        case .space: return trs("星空")
        case .goblin: return trs("苔蘚小窩")
        case .winter: return trs("雪夜")
        }
    }
    /// letters and numbers in the theme's own style
    var fontDesign: Font.Design {
        switch self {
        case .witch: return .serif
        case .goblin: return .rounded
        default: return .default
        }
    }
    static func sync(_ raw: String) { current = AppTheme(rawValue: raw) ?? .night }
}

/// one theme's colours
struct Palette {
    let bg: UInt32
    let key: UInt32
    let keyEdge: UInt32
    let fn: UInt32
    let fnEdge: UInt32
    let glyph: UInt32
    let muted: UInt32
    let blue: UInt32
    let blueEdge: UInt32
    let blueInk: UInt32
    let green: UInt32
    let greenEdge: UInt32
    let greenInk: UInt32
    let purpleInk: UInt32
    let olive: UInt32
    let oliveEdge: UInt32
    let oliveInk: UInt32
    let rust: UInt32
    let rustEdge: UInt32
    let rustInk: UInt32
    let pink: UInt32
    let guessInk: UInt32
    let swapInk: UInt32
    let pinkEdge: UInt32
    let pinkInk: UInt32
    let ownInk: UInt32
    let own: UInt32
    let ownEdge: UInt32
}

private enum P {
    static let night = Palette(bg: 0x1c1c1e, key: 0x4a4a4c, keyEdge: 0x6d6d70, fn: 0x2b2b2d, fnEdge: 0x4b4b4e, glyph: 0xf2f2f2, muted: 0xa3a3a8, blue: 0x34405e, blueEdge: 0x3d4f9c, blueInk: 0xc8cfff, green: 0x44503a, greenEdge: 0x4f6c32, greenInk: 0xd4efc0, purpleInk: 0xe3c6f7, olive: 0x5a5238, oliveEdge: 0x8c7a38, oliveInk: 0xf1e3ae, rust: 0x5b4136, rustEdge: 0x8b4a2d, rustInk: 0xf3c9b2, pink: 0x5e3a4f, guessInk: 0xff7a6e, swapInk: 0xff9fd2, pinkEdge: 0xa04a78, pinkInk: 0xf8cbe2, ownInk: 0xc39bff, own: 0x4c3a5b, ownEdge: 0x7b3c9b)
    static let witch = Palette(bg: 0x1b1611, key: 0x4a3b2c, keyEdge: 0x7d6242, fn: 0x2a221b, fnEdge: 0x5a4630, glyph: 0xf4ead5, muted: 0xb5a88d, blue: 0x2e3550, blueEdge: 0x56609a, blueInk: 0xdcd6ff, green: 0x3b4a31, greenEdge: 0x6e823d, greenInk: 0xe0ecc2, purpleInk: 0xe9cff1, olive: 0x5e4a2a, oliveEdge: 0xab853c, oliveInk: 0xf7dfab, rust: 0x5f3a29, rustEdge: 0xa0532f, rustInk: 0xf6c8a6, pink: 0x5a3442, guessInk: 0xff7a6e, swapInk: 0xff9fd2, pinkEdge: 0x9e4f6e, pinkInk: 0xf7cee0, ownInk: 0xcfa8ff, own: 0x4b3557, ownEdge: 0x8150a3)
    static let space = Palette(bg: 0x0b0e1a, key: 0x262e4a, keyEdge: 0x46578a, fn: 0x161b2e, fnEdge: 0x2f3a5e, glyph: 0xeef1ff, muted: 0x9aa3c7, blue: 0x1f2d5c, blueEdge: 0x3b5bd6, blueInk: 0xc6d4ff, green: 0x1d4446, greenEdge: 0x2f8f86, greenInk: 0xc4f5ec, purpleInk: 0xe2ccff, olive: 0x4f4220, oliveEdge: 0xc9a43a, oliveInk: 0xffe9a8, rust: 0x56283a, rustEdge: 0xb0446a, rustInk: 0xffc2d4, pink: 0x4a2858, guessInk: 0xff7a6e, swapInk: 0xff9fd2, pinkEdge: 0xa14fc2, pinkInk: 0xf3cdfc, ownInk: 0xc8b4ff, own: 0x372d66, ownEdge: 0x7a5cff)
    static let goblin = Palette(bg: 0x17170f, key: 0x3d3a24, keyEdge: 0x6e683a, fn: 0x25261a, fnEdge: 0x4d4a2c, glyph: 0xeee8d2, muted: 0xaaa58a, blue: 0x2c3a3a, blueEdge: 0x4f7470, blueInk: 0xcfe3dc, green: 0x34431f, greenEdge: 0x6b8a2e, greenInk: 0xdcedb4, purpleInk: 0xdcc7e6, olive: 0x4f4520, oliveEdge: 0x9c8a34, oliveInk: 0xf0e2a2, rust: 0x523222, rustEdge: 0x9a5a2c, rustInk: 0xf1caa6, pink: 0x4d3038, guessInk: 0xff7a6e, swapInk: 0xff9fd2, pinkEdge: 0x8e5464, pinkInk: 0xf0cfd6, ownInk: 0xc9b0e0, own: 0x3e3348, ownEdge: 0x75568a)
    /// 雪夜: frosty blue-grey, ice and pine
    static let winter = Palette(bg: 0x10161f, key: 0x2e3b4d, keyEdge: 0x5b7290, fn: 0x1a2330, fnEdge: 0x354659, glyph: 0xeef5ff, muted: 0x9fb0c4, blue: 0x24395a, blueEdge: 0x4f7fc0, blueInk: 0xcfe2ff, green: 0x1f3b3a, greenEdge: 0x3f8a83, greenInk: 0xc9f1ea, purpleInk: 0xdcd2fa, olive: 0x3d4656, oliveEdge: 0x8fa6c4, oliveInk: 0xe6eefb, rust: 0x4a2f3a, rustEdge: 0x9a5a6e, rustInk: 0xf6cdd8, pink: 0x40304f, guessInk: 0xff7a6e, swapInk: 0xff9fd2, pinkEdge: 0x8b5a9e, pinkInk: 0xf0d6f7, ownInk: 0xc6b4ff, own: 0x35304f, ownEdge: 0x6f5fb0)
    static var now: Palette {
        switch AppTheme.current {
        case .night: return night
        case .witch: return witch
        case .space: return space
        case .goblin: return goblin
        case .winter: return winter
        }
    }
}

/// The app's colours (方方之夜 = the same as the 方方 website and Safari extension), in the chosen theme.
enum T {
    static var bg: Color { Color(hex: P.now.bg) }
    static var key: Color { Color(hex: P.now.key) }
    static var keyEdge: Color { Color(hex: P.now.keyEdge) }
    static var fn: Color { Color(hex: P.now.fn) }
    static var fnEdge: Color { Color(hex: P.now.fnEdge) }
    static var glyph: Color { Color(hex: P.now.glyph) }
    static var muted: Color { Color(hex: P.now.muted) }
    static var blue: Color { Color(hex: P.now.blue) }
    static var blueEdge: Color { Color(hex: P.now.blueEdge) }
    static var blueInk: Color { Color(hex: P.now.blueInk) }
    static var green: Color { Color(hex: P.now.green) }
    static var greenEdge: Color { Color(hex: P.now.greenEdge) }
    static var greenInk: Color { Color(hex: P.now.greenInk) }
    static var purpleInk: Color { Color(hex: P.now.purpleInk) }
    /// buttons (what used to be green): 華語 blue, 台語 purple
    /// 華語 or 台語 now (kept in step by Store, readable from anywhere)
    nonisolated(unsafe) static var zh = false
    static var btn: Color { zh ? blue : own }
    static var btnEdge: Color { zh ? blueEdge : ownEdge }
    static var btnInk: Color { zh ? blueInk : purpleInk }
    static var olive: Color { Color(hex: P.now.olive) }
    static var oliveEdge: Color { Color(hex: P.now.oliveEdge) }
    static var oliveInk: Color { Color(hex: P.now.oliveInk) }
    static var rust: Color { Color(hex: P.now.rust) }
    static var rustEdge: Color { Color(hex: P.now.rustEdge) }
    static var rustInk: Color { Color(hex: P.now.rustInk) }
    static var pink: Color { Color(hex: P.now.pink) }
    static var guessInk: Color { Color(hex: P.now.guessInk) }
    static var swapInk: Color { Color(hex: P.now.swapInk) }
    static var pinkEdge: Color { Color(hex: P.now.pinkEdge) }
    static var pinkInk: Color { Color(hex: P.now.pinkInk) }
    static var ownInk: Color { Color(hex: P.now.ownInk) }
    static var own: Color { Color(hex: P.now.own) }
    static var ownEdge: Color { Color(hex: P.now.ownEdge) }

    /// 皓羅 / 台羅 / 白話字 text
    static func lat(_ size: CGFloat) -> Font { .custom("DejaVuSans", size: size) }
}

let ROM_NAMES = ["皓羅", "台羅", "白話字"]

/// the 10 places of the MOE dictionary's 語音差異, in the data's order (腔口 index = position)
let PLACE_NAMES = ["鹿港偏泉腔", "三峽偏泉腔", "臺北偏泉腔", "宜蘭偏漳腔", "臺南混合腔",
                   "高雄混合腔", "金門偏泉腔", "馬公偏泉腔", "新竹偏泉腔", "臺中偏漳腔"]

/// The spelling button (taps through 皓羅 → 台羅 → 白話字) with the 腔口 picker next to it.
/// It's in the top bar of every page except 設定.
struct RomButton: View {
    @AppStorage("rom") private var rom = 0
    private let glassOn = false   // the Liquid Glass look was taken out
    @ObservedObject private var store = Store.shared
    /// in a narrow place (手寫練習's word list on an iPad): the spelling and tone colour buttons on one row,
    /// the 腔口 picker under them
    var stacked = false
    var body: some View {
        if stacked {
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) { romButton; ToneMenu() }
                PlaceMenu(fill: true)       // as wide as the two above
            }
            .fixedSize()
        } else {
            row
        }
    }

    private var romButton: some View {
        Button {
            // 華語: 拼音 ⇄ 注音; 台語: 皓羅 → 台羅 → 白話字
            withAnimation(.snappy) { if store.isZh { store.zhRom = (store.zhRom + 1) % 2 } else { rom = (rom + 1) % 3 } }
        } label: {
            capsule
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("切換羅馬字"))
    }

    private var row: some View {
        HStack(spacing: 6) {
            Button {
                // 華語: 拼音 ⇄ 注音; 台語: 皓羅 → 台羅 → 白話字
                withAnimation(.snappy) { if store.isZh { store.zhRom = (store.zhRom + 1) % 2 } else { rom = (rom + 1) % 3 } }
            } label: {
                label
            }
            .accessibilityLabel(tr("切換羅馬字"))
            #if targetEnvironment(macCatalyst)
            .buttonStyle(.plain)          // Mac: the same one-tap capsule as on the phone, not a toolbar button
            .fixedSize()
            #endif
            PlaceMenu()
            ToneMenu()
        }
        #if targetEnvironment(macCatalyst)
        .fixedSize()
        #endif
    }

    @ViewBuilder private var label: some View {
        #if targetEnvironment(macCatalyst)
        capsule
        #else
        if glassOn {
            if #available(iOS 26.0, *) {
                plainText   // the iOS 26 toolbar already puts this in glass
            } else {
                capsule
            }
        } else {
            capsule
        }
        #endif
    }
    private var plainText: some View {
        Text(trs(store.isZh ? Lang.romNames[min(max(store.zhRom, 0), 1)] : ROM_NAMES[min(max(rom, 0), 2)]))
            .ffFont(.subheadline, .bold)
            .foregroundStyle(T.btnInk)
    }
    private var capsule: some View {
        plainText
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(T.btn))
            .overlay(Capsule().stroke(T.btnEdge, lineWidth: 2))
    }
}

struct Chip: View {
    let text: String
    var fill: Color = T.olive
    var edge: Color = T.oliveEdge
    var ink: Color = T.oliveInk
    var body: some View {
        Text(text)
            .ffFont(.caption, .bold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(edge, lineWidth: 1.5))
            .foregroundStyle(ink)
    }
}

/// 白 / 文 / 俗 label
struct RegChip: View {
    let reg: String
    var body: some View {
        switch reg {
        case "白": Chip(text: tr("白"), fill: T.green, edge: T.greenEdge, ink: T.greenInk)
        case "文": Chip(text: tr("文"), fill: T.blue, edge: T.blueEdge, ink: T.blueInk)
        case "俗": Chip(text: tr("俗"), fill: T.rust, edge: T.rustEdge, ink: T.rustInk)
        default: EmptyView()
        }
    }
}

struct NumBadge: View {
    let n: Int
    var body: some View {
        Text("\(n)")
            .ffFont(.caption2, .heavy)
            .frame(minWidth: 18, minHeight: 18)
            .background(Circle().fill(T.fn))
            .overlay(Circle().stroke(T.oliveEdge, lineWidth: 1.5))
            .foregroundStyle(T.oliveInk)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: 22), tint: T.fn.opacity(0.45))
    }
}

/// 腔口: 通行 or one of the 10 places
struct PlaceMenu: View {
    /// as wide as there's room for (RomButton stacked: as wide as the buttons above it)
    var fill = false
    @AppStorage("place") private var place = -1
    private let glassOn = false   // the Liquid Glass look was taken out
    @ObservedObject private var store = Store.shared
    var body: some View {
        Menu {
            // 台語 / 華語 first, then where it's said
            Picker(tr("語言"), selection: Binding(get: { store.isZh ? 1 : 0 }, set: { store.setLanguage(zh: $0 == 1) })) {
                Text(tr("台語")).tag(0)
                Text(tr("華語")).tag(1)
            }
            .pickerStyle(.inline)
            if store.isZh {
                Picker(tr("華語讀音"), selection: $store.zhPlace) {
                    ForEach(0..<Lang.placeNames.count, id: \.self) { Text(trs(Lang.placeNames[$0])).tag($0) }
                }
                .pickerStyle(.inline)
            } else {
                Picker(tr("台語腔口"), selection: $place) {
                    Text(tr("通行")).tag(-1)
                    ForEach(Array(PLACE_NAMES.enumerated()), id: \.offset) { i, p in Text(trs(p)).tag(i) }
                }
                .pickerStyle(.inline)         // the places right in the menu (on the Mac it was a submenu)
            }
        } label: {
            label
        }
        .accessibilityLabel(tr("腔口"))
        #if targetEnvironment(macCatalyst)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
    }

    private var name: String {
        if store.isZh { return "華・" + Lang.placeNames[min(max(store.zhPlace, 0), 1)] }
        return "台・" + (place >= 0 && place < PLACE_NAMES.count ? String(PLACE_NAMES[place].prefix(2)) : "通行")
    }

    /// always the coloured capsule (also with Liquid Glass), so you see at a glance which dictionary you're in:
    /// 台語 purple, 華語 blue
    private var label: some View { capsule }
    private var capsule: some View {
        plainText
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(store.isZh ? Color(hex: 0x1f3d6b) : Color(hex: 0x4c3a5b)))
            .overlay(Capsule().stroke(store.isZh ? Color(hex: 0x4f7dff) : Color(hex: 0x7b3c9b), lineWidth: 2))
    }
    private var plainText: some View {
        HStack(spacing: 2) {
            Text(name).ffFont(.subheadline, .bold)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .frame(maxWidth: fill ? .infinity : nil)
        .foregroundStyle(store.isZh ? Color(hex: 0x9ad0ff) : T.purpleInk)
    }
}

// MARK: text size (Mac)

/// Mac: how big the text is (設定 → 文字大小, or ⌘+ / ⌘− / ⌘0). iPhone and iPad follow the system's text size.
enum TextSize {
    static let levels: [DynamicTypeSize] = [.large, .xLarge, .xxLarge, .xxxLarge,
                                            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5]
    static let names = ["100%", "110%", "120%", "135%", "160%", "190%", "235%", "275%", "310%"]
    #if targetEnvironment(macCatalyst)
    static let key = "macTextSize2"
    static let standard = 3                   // 135%: the Mac's own text sizes are small on a big screen
    #else
    /// iPad (also the iPad app on a Mac): 100% = exactly as before (the system's text sizes)
    static let key = "padTextSize"
    static let standard = 0
    #endif
    /// the 文字大小 setting is shown: Mac, iPad, or the iPad app on a Mac (iPhone follows the system's size)
    static var onThisDevice: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return padScales
        #endif
    }
    /// iPad, or the iPad app running on a Mac: has its own text size setting (iPhone follows the system)
    static var padScales: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
    static func clamp(_ i: Int) -> Int { min(max(i, 0), levels.count - 1) }
}

struct MacTextSize: ViewModifier {
    @AppStorage(TextSize.key) private var level = TextSize.standard
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        // text without a style of its own (form rows, list rows…) at the chosen size too
        content.font(.system(size: 17 * 0.77 * TextSize.factor(level)))
            // and what the system draws itself (sidebar, menus, text fields), as far as it follows it
            .onAppear { MacWindow.applyTextSize(level) }
            .onChange(of: level) { MacWindow.applyTextSize(level) }
        #else
        if TextSize.padScales && level > 0 {
            // iPad: text without a style of its own, and what the system draws (form rows, lists), bigger too
            content.font(.system(size: 17 * TextSize.factor(level)))
                .dynamicTypeSize(TextSize.levels[TextSize.clamp(level)])
        } else {
            content
        }
        #endif
    }
}

extension TextSize {
    /// Mac: how much bigger than the Mac's own text sizes (100% = the system's size)
    static let factors: [CGFloat] = [1.0, 1.1, 1.2, 1.35, 1.6, 1.9, 2.35, 2.75, 3.1]
    static func factor(_ level: Int) -> CGFloat { factors[min(max(level, 0), factors.count - 1)] }
}

/// The app's text styles. On the Mac they're sized by 設定 → 文字大小 (the system ignores text size there);
/// on iPhone/iPad they're the usual text styles, which follow the phone's own text size.
enum FFStyle {
    case body, callout, subheadline, footnote, caption, caption2, headline, title3, title2, title, largeTitle
    var textStyle: Font.TextStyle {
        switch self {
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption
        case .caption2: return .caption2
        case .headline: return .headline
        case .title3: return .title3
        case .title2: return .title2
        case .title: return .title
        case .largeTitle: return .largeTitle
        }
    }
    var font: Font {
        switch self {
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption
        case .caption2: return .caption2
        case .headline: return .headline
        case .title3: return .title3
        case .title2: return .title2
        case .title: return .title
        case .largeTitle: return .largeTitle
        }
    }
    /// sizes on iPad (what the app was designed with)
    var size: CGFloat {
        switch self {
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        case .headline: return 17
        case .title3: return 20
        case .title2: return 22
        case .title: return 28
        case .largeTitle: return 34
        }
    }
}

struct FFFont: ViewModifier {
    let style: FFStyle
    var weight: Font.Weight? = nil
    var mono = false
    @AppStorage(TextSize.key) private var level = TextSize.standard
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        // Mac sizes are the iPad sizes × 0.77 (how Mac text compares to iPad text), then the chosen factor
        let f = Font.system(size: style.size * 0.77 * TextSize.factor(level),
                            weight: weight ?? (style == .headline ? .semibold : .regular))
        content.font(mono ? f.monospacedDigit() : f)
        #else
        if TextSize.padScales && level > 0 {
            let f = Font.system(size: style.size * TextSize.factor(level),
                                weight: weight ?? (style == .headline ? .semibold : .regular))
            content.font(mono ? f.monospacedDigit() : f)
        } else {
            let f = weight.map { style.font.weight($0) } ?? style.font
            content.font(mono ? f.monospacedDigit() : f)
        }
        #endif
    }
}

/// 皓羅 / 台羅 / 白話字 text (DejaVu Sans), sized with the Mac text size
struct LatFont: ViewModifier {
    let size: CGFloat
    @AppStorage(TextSize.key) private var level = TextSize.standard
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.font(.custom("DejaVuSans", fixedSize: size * 0.77 * TextSize.factor(level)))
        #else
        if TextSize.padScales && level > 0 {
            content.font(.custom("DejaVuSans", fixedSize: size * TextSize.factor(level)))
        } else {
            content.font(T.lat(size))
        }
        #endif
    }
}

/// a fixed-size system font that grows with the Mac text size (on iPhone/iPad it stays as it was)
struct ScaledFont: ViewModifier {
    private let size: CGFloat
    private let weight: Font.Weight
    private let on: Bool
    @AppStorage(TextSize.key) private var level = TextSize.standard
    init(_ size: CGFloat, weight: Font.Weight, on: Bool) {
        self.size = size; self.weight = weight; self.on = on
    }
    @ViewBuilder func body(content: Content) -> some View {
        if !on {
            content
        } else {
            #if targetEnvironment(macCatalyst)
            let s = size * 0.77 * TextSize.factor(level)
            #else
            let s = size * (TextSize.padScales ? TextSize.factor(level) : 1)
            #endif
            content.font(.system(size: s, weight: weight))
        }
    }
}

extension View {
    func macTextSize() -> some View { modifier(MacTextSize()) }
    func ffFont(_ style: FFStyle, _ weight: Font.Weight? = nil, mono: Bool = false) -> some View {
        modifier(FFFont(style: style, weight: weight, mono: mono))
    }
    func latFont(_ size: CGFloat) -> some View { modifier(LatFont(size: size)) }
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, on: Bool = true) -> some View {
        modifier(ScaledFont(size, weight: weight, on: on))
    }
}

/// Mac menu bar: 顯示 → 放大 / 縮小 / 實際大小
struct TextSizeCommands: Commands {
    @AppStorage(TextSize.key) private var level = TextSize.standard
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(tr("放大文字")) { level = TextSize.clamp(level + 1) }
                .keyboardShortcut("=", modifiers: .command)   // ⌘+ (the + key is ⇧=)
                .disabled(level >= TextSize.levels.count - 1)
            Button(tr("縮小文字")) { level = TextSize.clamp(level - 1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(level <= 0)
            Button(tr("實際大小")) { level = TextSize.standard }
                .keyboardShortcut("0", modifiers: .command)
        }
    }
}


// MARK: - the little cross that empties a text field

/// an ⓧ at the end of a text field while it has text: tapping it empties the field and puts the cursor in it,
/// so you can type the next thing straight away (TextEditor: the ⓧ sits in the bottom-right corner)
struct ClearButton: ViewModifier {
    @Binding var text: String
    var editor = false
    @FocusState private var focused: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if editor {
            content
                .focused($focused)
                .overlay(alignment: .bottomTrailing) { if !text.isEmpty { button.padding(6) } }
        } else {
            HStack(spacing: 6) {
                content.focused($focused)
                if !text.isEmpty { button }
            }
        }
    }

    private var button: some View {
        Button {
            text = ""
            focused = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(T.muted)
                .imageScale(.medium)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("清除"))
    }
}

extension View {
    /// an ⓧ that empties the field (and keeps typing in it)
    func clearButton(_ text: Binding<String>, editor: Bool = false) -> some View {
        modifier(ClearButton(text: text, editor: editor))
    }
}
