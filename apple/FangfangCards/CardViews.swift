import SwiftUI

/// The big swipeable card: 漢字, romanization, 方音, audio, meanings and one example.
struct WordCard: View {
    let card: Card
    var isTop = true
    @AppStorage(ToneColors.key) private var toneSys = 0
    @AppStorage(ToneColors.marksKey) private var toneMarks = false
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage("hideMeaning") private var hideMeaning = false
    @AppStorage(CardLook.hideReadingKey) private var hideReading = false
    @AppStorage(ZhMeaning.key) private var zhEnglish = false
    @State private var revealed = false
    @State private var showDetail = false
    @EnvironmentObject var store: Store

    /// the characters' size: big, smaller for longer words
    @Environment(\.compactCard) private var compact
    private var hanSize: CGFloat {
        let s: CGFloat = switch card.h.count { case 1: 150; case 2: 120; case 3: 92; case 4: 74; default: 58 }
        return compact ? s * 0.5 : s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            // the top: the meanings (numbered), and ▶
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    if hideMeaning && !revealed {
                        Text(tr("點一下看意思")).ffFont(.headline).foregroundStyle(T.muted)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else {
                        // 華語: the 詞類 (from the word lists)
                        if card.isZh, let pos = store.zh?.entry(card.k)?.pos, !pos.isEmpty {
                            HStack(spacing: 6) { ForEach(pos, id: \.self) { Chip(text: $0) } }
                        }
                        if let ens = englishMeanings {
                            // 設定 → 主要解釋: 英文 (numbered in blue)
                            ZhEnglishList(items: ens, max: compact ? 2 : 4, lineLimit: compact ? 1 : 2, font: compact ? .subheadline : .body)
                        } else {
                            let n = compact ? 2 : 4
                            ForEach(Array(card.d.prefix(n).enumerated()), id: \.offset) { i, d in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    NumBadge(n: i + 1)
                                    if !d.p.isEmpty { Chip(text: d.p) }
                                    Text(d.t).foregroundStyle(T.glyph).lineLimit(compact ? 1 : 2)
                                }
                            }
                            if card.d.count > n {
                                Text(tr("還有 \(card.d.count - n) 個意思")).ffFont(.caption).foregroundStyle(T.muted)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let a = card.audio { PlayButton(path: a, size: 44, onCard: true) }
            }
            Rectangle().fill(T.fnEdge).frame(height: 2)

            // the word, big in the middle, and how it's read
            Spacer(minLength: 0)
            VStack(spacing: compact ? 4 : 10) {
                Text(store.cardHan(card, place, base: T.blueInk)).toneGlow()
                    .scaledFont(hanSize, weight: .medium)
                    .lineLimit(1).minimumScaleFactor(0.3)
                if hideReading && !revealed {
                    // 設定 → 卡片上不顯示讀音: tap the card to see it
                    Text(tr("點一下看讀音")).ffFont(.subheadline).foregroundStyle(T.muted)
                } else {
                    Text(store.cardRom(card, rom, place)).latFont(compact ? 22 : 34).toneGlow().foregroundStyle(T.greenInk)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if !card.isZh {
                        Text(store.cardZy(card, place)).scaledFont(20).toneGlow().foregroundStyle(T.purpleInk)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                    if let x = store.alsoSaid(card, rom, place).first {
                        HStack(spacing: 6) {
                            Chip(text: tr("也講"), fill: Color(hex: 0x4c3a5b), edge: Color(hex: 0x7b3c9b), ink: T.purpleInk)
                            Text(x.rom).latFont(15).foregroundStyle(T.greenInk.opacity(0.85))
                        }
                    } else if let o = card.o?.first {
                        HStack(spacing: 6) {
                            Chip(text: o.l)
                            Text(o.r[min(max(rom, 0), 2)]).latFont(15).foregroundStyle(T.greenInk.opacity(0.85))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            HStack {
                CardChips(card: card, place: place)
                Spacer()
                Button { showDetail = true } label: {
                    Label(tr("詳細"), systemImage: "text.book.closed")
                        .ffFont(.footnote, .semibold)
                        .foregroundStyle(T.greenInk)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)   // frosted, so it doesn't stretch while the card moves
            }
        }
        .padding(compact ? 12 : 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(CardSurface(frosted: isTop))
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture { revealed.toggle() }
        .sheet(isPresented: $showDetail) { CardSheet(card: card).environmentObject(store) }
    }
}

extension WordCard {
    /// 華語 cards with 主要解釋 = 英文: the English meanings (nil = show the 華語 ones)
    var englishMeanings: [String]? {
        guard card.isZh, zhEnglish, Lang.charOf(card.k) == nil, let e = store.zh?.entry(card.k) else { return nil }
        let l = e.enList
        return l.isEmpty ? nil : l
    }
}

/// 設定 → 卡片與練習
enum CardLook {
    /// the cards don't show the reading until you tap them
    static let hideReadingKey = "hideReading"
}

/// Green / rust glow from the side you swipe toward, plus a soft highlight under the finger.
/// Kept separate from WordCard so dragging only redraws this, not the whole card.
struct CardLight: View {
    let swipe: CGFloat        // -1 … 1
    let touch: CGPoint?

    var body: some View {
        let color = swipe > 0 ? T.blueEdge : T.rustEdge
        let a = Double(min(abs(swipe), 1))
        return GeometryReader { g in
            ZStack {
                if a > 0.02 {
                    LinearGradient(colors: [color.opacity(0.55 * a), color.opacity(0)],
                                   startPoint: swipe > 0 ? .trailing : .leading,
                                   endPoint: swipe > 0 ? .leading : .trailing)
                    RoundedRectangle(cornerRadius: 28).strokeBorder(color.opacity(0.9 * a), lineWidth: 3)
                }
                if let p = touch, g.size.width > 0, g.size.height > 0 {
                    RadialGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                                   center: UnitPoint(x: p.x / g.size.width, y: p.y / g.size.height),
                                   startRadius: 0, endRadius: 200)
                        .blendMode(.plusLighter)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .allowsHitTesting(false)
    }
}

/// Everything about one word: all meanings and all examples.
struct CardDetail: View {
    let card: Card
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Panel {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(card.h).scaledFont(44, weight: .medium).foregroundStyle(T.blueInk)
                                Spacer()
                                CardChips(card: card, place: place)
                                if let a = card.audio { PlayButton(path: a, size: 40) }
                            }
                            Text(store.cardRom(card, rom, place)).latFont(24).foregroundStyle(T.greenInk)
                            Text(store.cardZy(card, place)).scaledFont(17).foregroundStyle(T.purpleInk)
                            // other readings, and the 通行 one when a place is shown
                            ForEach(Array(store.alsoSaid(card, rom, place).enumerated()), id: \.offset) { _, x in
                                OtherRow(label: trs("也講"), rom: x.rom, zy: x.zy)
                            }
                            if store.cardDiffers(card, place), !store.alsoSaid(card, rom, place).contains(where: { $0.rom == card.rom(rom) }) {
                                OtherRow(label: trs("通行"), rom: card.rom(rom), zy: card.z)
                            }
                            // 華語: the 臺灣 / 大陸 reading that isn't shown, where they differ
                            if card.isZh, let zl = card.zl, let d = store.zh {
                                let tw = store.zhPlace == 1
                                OtherRow(label: tw ? trs("臺灣") : trs("大陸"), rom: d.readingPlain(tw ? card.zs ?? [] : zl, store.zhRom), zy: "")
                            }
                            ForEach(Array((card.o ?? []).enumerated()), id: \.offset) { _, o in
                                OtherRow(label: o.l, rom: o.r[min(max(rom, 0), 2)], zy: o.z)
                            }
                            if let cs = card.cats, !cs.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(cs, id: \.self) { i in
                                        if let t = store.topics.first(where: { $0.id == i }) { Chip(text: t.name, fill: T.fn, edge: T.fnEdge, ink: T.muted) }
                                    }
                                }
                                .padding(.top, 2)
                            }
                            Text(statusText).ffFont(.caption).foregroundStyle(T.muted).padding(.top, 4)
                        }
                    }
                    ForEach(Array(card.d.enumerated()), id: \.offset) { i, d in
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    NumBadge(n: i + 1)
                                    if !d.p.isEmpty { Chip(text: d.p) }
                                    Text(d.t).foregroundStyle(T.glyph)
                                }
                                LinkRows(sy: d.sy, an: d.an)
                                ForEach(Array(d.x.enumerated()), id: \.offset) { _, x in
                                    HStack(alignment: .top, spacing: 10) {
                                        PlayButton(path: Audio.examplePath(x.n), size: 28)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(store.exampleHan(card, x, place))
                                            Text(store.exampleRom(card, x, rom, place)).latFont(15).foregroundStyle(T.greenInk)
                                            Text(x.z).ffFont(.footnote).foregroundStyle(T.muted)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if store.cardHasGuess(card, place) { GuessNote() }
                    if card.sy != nil || card.an != nil {
                        Panel { LinkRows(sy: card.sy, an: card.an) }
                    }
                    if card.t == "臺華共同" {
                        Text(tr("臺華共同詞：意思跟華語一樣。")).ffFont(.footnote).foregroundStyle(T.muted)
                    }
                    HStack(spacing: 12) {
                        Button { store.mark(card, known: false, undoable: false); dismiss() } label: {
                            Label(tr("不熟"), systemImage: "xmark").frame(maxWidth: .infinity)
                        }
                        .prominentButton(T.rustEdge)
                        Button { store.mark(card, known: true, undoable: false); dismiss() } label: {
                            Label(tr("熟悉"), systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .prominentButton(T.btnEdge)
                    }
                    .padding(.top, 4)
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle(card.h)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { RomButton() }
                ToolbarItem(placement: .topBarTrailing) { Button(tr("完成")) { dismiss() } }
            }
        }
    }

    private var statusText: String {
        switch store.status(card) {
        case 1?: return trs("熟悉")
        case 2?: return tr("不熟（連續答對 \(store.streak(card)) 次）")
        default: return trs("還沒看過")
        }
    }
}

/// One row in the 不熟 / 熟悉 lists.
struct WordRow: View {
    let card: Card
    @EnvironmentObject var store: Store
    var streak: Int? = nil
    var goal: Int = 3
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.h).ffFont(.title3, .medium).foregroundStyle(T.blueInk)
                    Text(store.cardRom(card, rom, place)).latFont(16).foregroundStyle(T.greenInk)
                    Text(store.cardZy(card, place)).ffFont(.footnote).foregroundStyle(T.purpleInk)
                }
                Text(card.firstMeaning).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(1)
            }
            Spacer()
            if let s = streak {
                HStack(spacing: 3) {
                    ForEach(0..<goal, id: \.self) { i in
                        Circle().fill(i < s ? T.greenInk : T.fnEdge).frame(width: 7, height: 7)
                    }
                }
                .accessibilityLabel(tr("答對 \(s) 次"))
            }
        }
        .padding(.vertical, 2)
    }
}


/// 白/文/俗, 替, 臺華共同, and the place when its reading is shown
struct CardChips: View {
    let card: Card
    let place: Int
    @EnvironmentObject var store: Store
    var body: some View {
        HStack(spacing: 4) {
            RegChip(reg: card.g)
            if card.s == 1 { Chip(text: tr("替"), fill: T.rust, edge: T.rustEdge, ink: T.rustInk) }
            if let t = card.t { Chip(text: t, fill: T.fn, edge: T.fnEdge, ink: T.muted) }
            if store.cardDiffers(card, place), place < store.places.count {
                Chip(text: String(store.places[place].prefix(2)), fill: Color(hex: 0x4c3a5b), edge: Color(hex: 0x7b3c9b), ink: T.purpleInk)
                if store.isGuessed(card, place) { Chip(text: tr("推測"), fill: T.fn, edge: T.fnEdge, ink: T.muted) }
            }
        }
    }
}

struct OtherRow: View {
    let label: String
    let rom: String
    let zy: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Chip(text: label)
            Text(rom).latFont(17).foregroundStyle(T.greenInk)
            Text(zy).ffFont(.footnote).foregroundStyle(T.purpleInk)
        }
    }
}

/// 近義 / 反義 words
struct LinkRows: View {
    let sy: [[String]]?
    let an: [[String]]?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(trs("近"), sy)
            row(trs("反"), an)
        }
    }
    @ViewBuilder private func row(_ name: String, _ list: [[String]]?) -> some View {
        if let list, !list.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Chip(text: name, fill: T.blue, edge: T.blueEdge, ink: T.blueInk)
                Text(list.map { $0.count > 1 && !$0[1].isEmpty ? "\($0[0]) \($0[1])" : $0[0] }.joined(separator: "、"))
                    .ffFont(.footnote).foregroundStyle(T.glyph.opacity(0.85))
            }
        }
    }
}


/// 詳細 / a word from the lists: the dictionary entry in a sheet from the bottom, like everywhere else
/// (the card's own details until the dictionary has loaded)
struct CardSheet: View {
    let card: Card
    @EnvironmentObject var store: Store
    var body: some View {
        Group {
            if card.isZh, let z = store.zh, let ch = Lang.charOf(card.k), z.charIndex[ch] != nil {
                ZhCharSheet(dict: z, ch: ch)
            } else if card.isZh, let z = store.zh, z.entry(card.k) != nil {
                ZhEntrySheet(dict: z, key: card.k)
            } else if let d = store.dict, d.raw.defs.m[card.k] != nil || d.baseKeys.contains(card.k) {
                WordEntrySheet(dict: d, key: card.k)
            } else {
                CardDetail(card: card)
                    .presentationDetents([.medium, .large])
                    .presentationContentInteraction(.scrolls)
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear { if !card.isZh { store.loadDict() } }
    }
}
