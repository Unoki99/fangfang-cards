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
    case night, witch, space, goblin, winter, sakura, momiji
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
        case .sakura: return trs("夜櫻")
        case .momiji: return trs("紅葉狩")
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
    /// 夜櫻: cherry blossoms at night, plum dark and petal pink
    static let sakura = Palette(bg: 0x1d1418, key: 0x4c3440, keyEdge: 0x8e5d73, fn: 0x2a1c22, fnEdge: 0x5b3a49, glyph: 0xfdeff4, muted: 0xc7a9b6, blue: 0x353a5e, blueEdge: 0x5a66a8, blueInk: 0xd2d6ff, green: 0x37473a, greenEdge: 0x6a8a62, greenInk: 0xd6ecd0, purpleInk: 0xeacdf5, olive: 0x584a33, oliveEdge: 0xa88a52, oliveInk: 0xf6e3b5, rust: 0x5e3240, rustEdge: 0xb85878, rustInk: 0xffc8d8, pink: 0x6a3550, guessInk: 0xff7a6e, swapInk: 0xff9fd2, pinkEdge: 0xe07aa6, pinkInk: 0xffd3e6, ownInk: 0xd6b0ff, own: 0x4a3358, ownEdge: 0x8b5fb0)
    /// 紅葉狩: an autumn evening, maple red and gold
    static let momiji = Palette(bg: 0x1c130f, key: 0x4c2f22, keyEdge: 0x9a4f2c, fn: 0x2a1b14, fnEdge: 0x5e3524, glyph: 0xf9ece2, muted: 0xc6a898, blue: 0x2f3550, blueEdge: 0x56619a, blueInk: 0xd4d8ff, green: 0x3d4529, greenEdge: 0x7f8a3a, greenInk: 0xe4ecc0, purpleInk: 0xe9cfe6, olive: 0x5e4520, oliveEdge: 0xc9922e, oliveInk: 0xfde3a6, rust: 0x632a1c, rustEdge: 0xd2552b, rustInk: 0xffc6a8, pink: 0x5c2e34, guessInk: 0xff7a6e, swapInk: 0xff9fd2, pinkEdge: 0xb5545f, pinkInk: 0xf9cdd2, ownInk: 0xd0b0ef, own: 0x45304f, ownEdge: 0x86579f)
    static var now: Palette {
        switch AppTheme.current {
        case .night: return night
        case .witch: return witch
        case .space: return space
        case .goblin: return goblin
        case .winter: return winter
        case .sakura: return sakura
        case .momiji: return momiji
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
    /// 粵語 shown (its buttons are yellow)
    nonisolated(unsafe) static var yue = false
    /// 客語 shown (its buttons are red)
    nonisolated(unsafe) static var hak = false
    /// 日語 shown (its buttons are pink)
    nonisolated(unsafe) static var ja = false
    static var btn: Color { ja ? jaFill : (hak ? hakFill : (yue ? olive : (zh ? blue : twFill))) }
    static var btnEdge: Color { ja ? jaEdge : (hak ? hakEdge : (yue ? oliveEdge : (zh ? blueEdge : twEdge))) }
    static var btnInk: Color { ja ? jaInk : (hak ? hakInk : (yue ? oliveInk : (zh ? blueInk : twInk))) }
    /// 日語's pink (the same in every theme)
    static let jaFill = Color(hex: 0x5a2346), jaEdge = Color(hex: 0xff8cc6), jaInk = Color(hex: 0xffc9e4)
    /// 台語's green (the same in every theme)
    static let twFill = Color(hex: 0x1d4630), twEdge = Color(hex: 0x3fae66), twInk = Color(hex: 0xb6f0c8)
    /// 客語's red (the same in every theme)
    static let hakFill = Color(hex: 0x5a1e2a), hakEdge = Color(hex: 0xd8434f), hakInk = Color(hex: 0xffb3b8)
    /// each language's capsule (the language menu): fill, edge, ink
    static func langColors(_ l: Int) -> (fill: Color, edge: Color, ink: Color) {
        switch l {
        case 4: return (jaFill, jaEdge, jaInk)
        case 3: return (hakFill, hakEdge, hakInk)
        case 2: return (Color(hex: 0x5a4a14), Color(hex: 0xc9a227), Color(hex: 0xffe58a))
        case 1: return (Color(hex: 0x1f3d6b), Color(hex: 0x4f7dff), Color(hex: 0x9ad0ff))
        default: return (twFill, twEdge, twInk)
        }
    }
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

let ROM_NAMES = ["皓羅", "台羅", "白話字", "方音"]

/// 台語's spelling: 0 皓羅, 1 台羅, 2 白話字 (each with 方音 under it), or 3 = 方音 only
enum TwRom {
    static var hongimOnly: Bool { UserDefaults.standard.integer(forKey: "rom") == 3 }
    /// the spelling of the main reading line (3: 方音)
    static func lat(_ rom: Int) -> Int { rom == 3 ? 3 : min(max(rom, 0), 2) }
}

/// the 方音 line under a 台語 reading: left out when 方音 is the only spelling (it's the main line then)
struct HongimLine: ViewModifier {
    @AppStorage("rom") private var rom = 0
    @ViewBuilder func body(content: Content) -> some View {
        if rom != 3 { content }
    }
}
extension View {
    func hongimLine() -> some View { modifier(HongimLine()) }
}

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
        Text(trs(store.isZh ? Lang.romNames[min(max(store.zhRom, 0), 1)] : ROM_NAMES[TwRom.lat(rom)]))
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
/// the language, then where it's said (in PlaceMenu, and in the one menu of a narrow top bar)
struct PlaceMenuItems: View {
    @AppStorage("place") private var place = -1
    @ObservedObject private var store = Store.shared
    var body: some View {
        // 台語 / 華語 / 粵語 first, then where it's said
        Picker(tr("語言"), selection: Binding(get: { store.lang }, set: { store.setLanguage($0) })) {
            Text(tr("台語")).tag(0)
            Text(tr("華語")).tag(1)
            Text(tr("粵語")).tag(2)
            Text(tr("客語")).tag(3)
            Text(tr("日語")).tag(4)
        }
        .pickerStyle(.inline)
        if store.isYue || store.isJa {
            EmptyView()       // (粵語, 日語: one reading)
        } else if store.isHak {
            Picker(tr("客語腔"), selection: $store.hakAccent) {
                ForEach(0..<Lang.hakAccents.count, id: \.self) { Text(trs(Lang.hakAccents[$0])).tag($0) }
            }
            .pickerStyle(.inline)
        } else if store.isZh {
            Picker(tr("華語讀音"), selection: $store.zhPlace) {
                ForEach(0..<Lang.zhPlaceNames.count, id: \.self) { Text(trs(Lang.zhPlaceNames[$0])).tag($0) }
            }
            .pickerStyle(.inline)
        } else {
            Picker(tr("台語腔口"), selection: $place) {
                Text(tr("通行")).tag(-1)
                ForEach(Array(PLACE_NAMES.enumerated()), id: \.offset) { i, p in Text(trs(p)).tag(i) }
            }
            .pickerStyle(.inline)         // the places right in the menu (on the Mac it was a submenu)
        }
    }
}

/// a narrow top bar (iPhone held upright): the spelling, the language and place and the tone colours in one
/// menu; its button shows the spelling and the tone colours, in the language's colour (台語 purple, 華語 blue,
/// 粵語 yellow)
struct CompactReadingMenu: View {
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage(ToneColors.key) private var system = 0
    @AppStorage(ToneColors.versionKey) private var colorVersion = 0
    @ObservedObject private var store = Store.shared
    var body: some View {
        Menu {
            Section(tr("拼寫")) {
                if store.isZh {
                    Picker(tr("拼寫"), selection: $store.zhRom) {
                        ForEach(0..<Lang.romNames.count, id: \.self) { Text(trs(Lang.romNames[$0])).tag($0) }
                    }
                    .pickerStyle(.inline)
                } else {
                    Picker(tr("拼寫"), selection: $rom) {
                        ForEach(0..<ROM_NAMES.count, id: \.self) { Text(trs(ROM_NAMES[$0])).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }
            PlaceMenuItems()
            Menu {
                ToneMenuItems()
            } label: { Label(tr("聲調顏色"), systemImage: "paintpalette") }
        } label: {
            HStack(spacing: 5) {
                Text(trs(store.isZh ? Lang.romNames[min(max(store.zhRom, 0), 1)] : ROM_NAMES[TwRom.lat(rom)]))
                    .ffFont(.subheadline, .bold)
                    .lineLimit(1)
                ToneDots(system: system)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(T.langColors(store.lang).ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(T.langColors(store.lang).fill))
            .overlay(Capsule().stroke(T.langColors(store.lang).edge, lineWidth: 2))
            .id(colorVersion)
        }
        .accessibilityLabel(tr("讀音和聲調顏色"))
    }
}

struct PlaceMenu: View {
    /// as wide as there's room for (RomButton stacked: as wide as the buttons above it)
    var fill = false
    @AppStorage("place") private var place = -1
    private let glassOn = false   // the Liquid Glass look was taken out
    @ObservedObject private var store = Store.shared
    var body: some View {
        Menu {
            PlaceMenuItems()
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

    private var name: String { PlaceMenu.name(store, place) }
    static func name(_ store: Store, _ place: Int) -> String {
        if store.isYue { return "粵語" }
        if store.isJa { return "日語" }
        if store.isHak { return "客・" + Lang.hakAccents[min(max(store.hakAccent, 0), Lang.hakAccents.count - 1)] }
        if store.isZh { return "華・" + Lang.zhPlaceNames[min(max(store.zhPlace, 0), Lang.zhPlaceNames.count - 1)] }
        return "台・" + (place >= 0 && place < PLACE_NAMES.count ? String(PLACE_NAMES[place].prefix(2)) : "通行")
    }

    /// always the coloured capsule (also with Liquid Glass), so you see at a glance which dictionary you're in:
    /// 台語 purple, 華語 blue
    private var label: some View { capsule }
    private var capsule: some View {
        plainText
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(T.langColors(store.lang).fill))
            .overlay(Capsule().stroke(T.langColors(store.lang).edge, lineWidth: 2))
    }
    private var plainText: some View {
        HStack(spacing: 2) {
            Text(name).ffFont(.subheadline, .bold)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .frame(maxWidth: fill ? .infinity : nil)
        .foregroundStyle(T.langColors(store.lang).ink)
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
    var uiStyle: UIFont.TextStyle {
        switch self {
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        case .headline: return .headline
        case .title3: return .title3
        case .title2: return .title2
        case .title: return .title1
        case .largeTitle: return .largeTitle
        }
    }
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

/// 設定 → 詞典 → 字體: the text of a dictionary entry (a word's or a character's page) in the system font or in one
/// of the handwriting fonts (楷體, 文楷, 芫荽)
/// 設定 → 顏色與外觀 → 字體: the app's 漢字 and kana in the system font or in one of the handwriting fonts (楷體, 文楷,
/// 芫荽). Only the characters the system font doesn't have change: English and the readings stay as they are.
enum DictFont {
    static let key = "dictFont"
    /// 0 = the system font, then Kaiti.styles
    static var names: [String] { ["系統字體"] + Kaiti.styles.map { $0.name } }
    static var chosen: Int { UserDefaults.standard.integer(forKey: key) }

    /// the system font at a size and weight, its 漢字 and kana from the handwriting font chosen (nil: the system
    /// font as it is). The system font has no 漢字: what it doesn't have is looked for in its cascade list first, so
    /// putting the handwriting font there changes only those characters.
    static func font(_ size: CGFloat, weight: Font.Weight = .regular, on: Bool = true) -> Font? {
        let c = chosen
        guard on, c > 0 else { return nil }
        let key = "\(c)|\(size)|\(weight.hashValue)" as NSString
        if let hit = cache.object(forKey: key) { return Font(hit as CTFont) }
        Kaiti.register()
        let chosenName = Kaiti.styles[min(c - 1, Kaiti.styles.count - 1)].ps
        let names = [chosenName] + ["LXGWWenKaiTC-Regular", Kaiti.tc, Kaiti.sc].filter { $0 != chosenName }
        let have = names.filter { UIFont(name: $0, size: size) != nil }
        guard !have.isEmpty else { return nil }
        let base = UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        let desc = base.fontDescriptor.addingAttributes([.cascadeList: have.map { UIFontDescriptor(name: $0, size: size) }])
        let f = UIFont(descriptor: desc, size: size)
        cache.setObject(f, forKey: key)
        return Font(f as CTFont)
    }
    private static let cache: NSCache<NSString, UIFont> = { let c = NSCache<NSString, UIFont>(); c.countLimit = 200; return c }()

    private static func uiWeight(_ w: Font.Weight) -> UIFont.Weight {
        switch w {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

private struct InEntryKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// inside a dictionary entry (its text follows 設定 → 詞典 → 字體)
    var inEntry: Bool {
        get { self[InEntryKey.self] }
        set { self[InEntryKey.self] = newValue }
    }
}
extension View {
    /// a dictionary entry: its text in the font chosen in 設定 → 詞典 → 字體
    func dictFontArea() -> some View { environment(\.inEntry, true) }
}

struct FFFont: ViewModifier {
    let style: FFStyle
    var weight: Font.Weight? = nil
    var mono = false
    @AppStorage(TextSize.key) private var level = TextSize.standard
    @AppStorage(DictFont.key) private var dictFont = 0
    @Environment(\.inEntry) private var inEntry
    @ViewBuilder func body(content: Content) -> some View {
        // 字體 = a handwriting font: the 漢字 and kana in it (the text style's size, grown with the text size chosen)
        if dictFont > 0, let f = DictFont.font(fontSize, weight: weight ?? (style == .headline ? .semibold : .regular)) {
            content.font(mono ? f.monospacedDigit() : f)
        } else {
            plain(content)
        }
    }
    private var fontSize: CGFloat {
        #if targetEnvironment(macCatalyst)
        return style.size * 0.77 * TextSize.factor(level)
        #else
        return TextSize.padScales && level > 0 ? style.size * TextSize.factor(level)
            : UIFontMetrics(forTextStyle: style.uiStyle).scaledValue(for: style.size)
        #endif
    }
    @ViewBuilder private func plain(_ content: Content) -> some View {
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
    @AppStorage(DictFont.key) private var dictFont = 0
    @Environment(\.inEntry) private var inEntry
    init(_ size: CGFloat, weight: Font.Weight, on: Bool) {
        self.size = size; self.weight = weight; self.on = on
    }
    private var scaledSize: CGFloat {
        #if targetEnvironment(macCatalyst)
        return size * 0.77 * TextSize.factor(level)
        #else
        return size * (TextSize.padScales ? TextSize.factor(level) : 1)
        #endif
    }
    @ViewBuilder func body(content: Content) -> some View {
        if !on {
            content
        } else if dictFont > 0, let f = DictFont.font(scaledSize, weight: weight) {
            // 字體 = a handwriting font: the 漢字 and kana in it
            content.font(f)
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
        // 設定… in the app's menu (⌘,): on a Mac the ⚙︎ in the top bar can be left out when the window's bar is full
        CommandGroup(replacing: .appSettings) {
            Button(tr("設定…")) { Task { @MainActor in Router.shared.settingsOpen = true } }
                .keyboardShortcut(",", modifiers: .command)
        }
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
