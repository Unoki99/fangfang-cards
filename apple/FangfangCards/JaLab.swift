import SwiftUI

// MARK: - 日語's own pages, in the app's look: 活用 and 漢字 in a word's entry, 助詞, 助詞練習, 實驗室, 顏色
//
// Everything else of 日語 is the same pages as the other languages (新詞, 不熟, 詞典, 熟悉, 練習).

// MARK: the colours (設定 → 顏色與外觀 → 選日語的顏色)

struct JaColorSettings: View {
    @State private var version = 0
    var body: some View {
        SettingsPage(title: tr("日語的顏色")) {
            Section {
                ForEach(0..<JaColors.keys.count, id: \.self) { i in
                    ColorPicker(trs(JaColors.names[i]), selection: Binding(
                        get: { JaColors.color(i) },
                        set: { c in UserDefaults.standard.set(Self.hex(c), forKey: JaColors.keys[i]); version += 1 }),
                                supportsOpacity: false)
                }
            } footer: {
                Text(JaInk.attributed(JaInk.marked("猫[が]ミルク[を]飲み{ます}。"))).scaledFont(28).padding(.top, 10).id(version)
            }
            Section {
                Button(tr("恢復原本的顏色")) {
                    for k in JaColors.keys { UserDefaults.standard.removeObject(forKey: k) }
                    version += 1
                }
            }
        }
    }
    static func hex(_ c: Color) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        func n(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return (n(r) << 16) | (n(g) << 8) | n(b)
    }
}

// MARK: a word's entry: its kanji and its 活用

struct JaWordExtras: View {
    let dict: ZhDict
    let entry: ZhEntry
    @EnvironmentObject var store: Store

    /// the word's kanji, each once
    private var kanji: [String] {
        var out: [String] = []
        for c in entry.h where JaKana.isKanji(c) && !out.contains(String(c)) { out.append(String(c)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // each kanji of a longer word: its card (a one-kanji word shows it at the top already)
            if entry.h.count > 1 {
                ForEach(kanji, id: \.self) { ch in
                    if dict.charIndex[ch] != nil { JaKanjiRow(dict: dict, ch: ch) }
                }
            }
            if case let (c, t)? = JaGrammar.classOf(entry) {
                JaConjugationBlock(entry: entry, cls: c, text: t)
                NavigationLink { JaLabPage(dict: dict, start: entry) } label: {
                    TileLabel(icon: "slider.horizontal.3", title: trs("在實驗室組合這個詞"))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// one kanji of a word: its readings and meanings (KANJIDIC2), and its card
struct JaKanjiRow: View {
    let dict: ZhDict
    let ch: String
    @EnvironmentObject var store: Store
    @State private var open = false
    var body: some View {
        if let i = dict.charIndex[ch] {
            let c = dict.chars[i]
            Button { open = true } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(dict.hanText(ch, [], base: T.glyph)).scaledFont(40, weight: .semibold).toneGlow()
                    VStack(alignment: .leading, spacing: 4) {
                        if let r = c.readings.first {
                            Text(dict.reading([r.zy], store.zhRom)).latFont(15).foregroundStyle(T.greenInk).lineLimit(2)
                            Text(r.defs.filter { !$0.text.hasPrefix("例：") }.prefix(4).map(\.text).joined(separator: ", "))
                                .ffFont(.subheadline).foregroundStyle(T.glyph).lineLimit(2)
                        }
                        if let n = c.strokes { Text(tr("\(n) 畫")).ffFont(.caption).foregroundStyle(T.muted) }
                    }
                    Spacer(minLength: 0)
                    let st = store.cardStatus(Lang.charKey(ch)) ?? 0
                    if st == 1 { Image(systemName: "checkmark.circle.fill").foregroundStyle(T.greenInk) }
                    else if st == 2 { Image(systemName: "star.fill").foregroundStyle(T.rustInk) }
                    Image(systemName: "chevron.right").ffFont(.caption).foregroundStyle(T.muted)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $open) { ZhCharSheet(dict: dict, ch: ch).environmentObject(store) }
        }
    }
}

/// 活用: every form of a verb or adjective in groups (plain and polite side by side, the voices together, the
/// conditionals together), the word in its colours (the ending in the ending colour)
struct JaConjugationBlock: View {
    let entry: ZhEntry
    let cls: JaClass
    let text: String
    @EnvironmentObject var store: Store
    @Environment(\.horizontalSizeClass) private var hsc

    var body: some View {
        let groups = JaGrammar.groups(for: cls)
        let wide = hsc == .regular
        // two-form groups two to a row on an iPad; bigger ones a row of their own; the one-form groups together
        let pairs = groups.filter { $0.rows.count == 2 }
        let bigs = groups.filter { $0.rows.count > 2 }
        let singles = groups.filter { $0.rows.count == 1 }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(tr("活用")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                InfoChip.yellow(trs(cls.name))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: wide ? 2 : 1), spacing: 10) {
                ForEach(pairs) { group($0, columns: 2) }
            }
            ForEach(bigs) { group($0, columns: wide ? $0.rows.count : 2) }
            if !singles.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: wide ? singles.count : min(2, singles.count)), spacing: 10) {
                    ForEach(singles) { group($0, columns: 1) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
    }

    /// a group: its name in its colour, then its forms side by side
    private func group(_ g: JaGrammar.ConjGroup, columns: Int) -> some View {
        let tint = Color(hex: g.color)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(trs(g.name)).ffFont(.caption, .bold).foregroundStyle(tint)
                Text(g.en).ffFont(.caption2).foregroundStyle(T.muted).lineLimit(1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: max(1, columns)), alignment: .leading, spacing: 8) {
                ForEach(g.rows, id: \.0) { form($0) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.45), lineWidth: 1.5))
    }

    @ViewBuilder private func form(_ row: (String, String, [String])) -> some View {
        let reading = JaGrammar.readingOf(entry, cls)
        let hasKanji = entry.h.contains { JaKana.isKanji($0) }
        if let ch = JaGrammar.Chain(text, cls).adding(row.2) {
            let r = JaGrammar.Chain(reading, cls).adding(row.2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(trs(row.0)).ffFont(.caption, .bold).foregroundStyle(T.muted)
                    Spacer(minLength: 4)
                    Text(row.1).ffFont(.caption2).foregroundStyle(T.muted).lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(JaInk.attributed(ch.pieces)).scaledFont(21, weight: .semibold).toneGlow().textSelection(.enabled)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if hasKanji, let r {
                    Text(store.zhRom == 0 ? AttributedString(JaKana.romaji(r.text)) : JaInk.attributed(r.pieces))
                        .latFont(13).foregroundStyle(T.greenInk).lineLimit(1).minimumScaleFactor(0.6)
                } else if store.zhRom == 0 {
                    Text(JaKana.romaji(ch.text)).latFont(13).foregroundStyle(T.greenInk).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(T.fn.opacity(0.7)))
        }
    }
}

// MARK: - 助詞: the map, the groups, each with examples

struct JaParticlesPage: View {
    @State private var open: JaParticle?
    @State private var quiz = false
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button { quiz = true } label: { TileLabel(icon: "puzzlepiece", title: trs("助詞練習")) }
                    .buttonStyle(.plain)
                map
                ForEach(JaParticles.groups, id: \.0) { g in
                    let ps = JaParticles.all.filter { $0.group == g.0 }
                    if !ps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Chip(text: trs(g.0), fill: T.btn, edge: T.btnEdge, ink: T.btnInk)
                                Text(g.1).ffFont(.caption).foregroundStyle(T.muted)
                            }
                            ForEach(ps) { p in row(p) }
                        }
                    }
                }
                Text(tr("說明和例句是方方詞卡自己寫的。")).ffFont(.caption2).foregroundStyle(T.muted)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle(tr("助詞"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $open) { p in JaParticleSheet(p: p).environmentObject(store) }
        .fullScreenCover(isPresented: $quiz) { JaParticleQuiz().environmentObject(store) }
    }

    private func row(_ p: JaParticle) -> some View {
        Button { open = p } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(p.p).scaledFont(26, weight: .semibold).foregroundStyle(JaColors.particle).toneGlow().frame(minWidth: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trs(p.zh)).ffFont(.subheadline).foregroundStyle(T.glyph).multilineTextAlignment(.leading)
                    if let ex = p.ex.first { Text(JaInk.attributed(JaInk.marked(ex.0))).scaledFont(17).toneGlow() }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").ffFont(.caption).foregroundStyle(T.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// 用法地圖: one sentence, each particle under it with what it does; then the order of a sentence
    private var map: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("用法地圖")).ffFont(.caption, .bold).foregroundStyle(T.muted)
            FlowLayout(spacing: 4, lineSpacing: 10) {
                ForEach(Array(JaInk.marked(JaParticles.mapSentence).enumerated()), id: \.offset) { _, piece in
                    if piece.kind == .particle, let p = JaParticles.all.first(where: { $0.p == piece.text }) {
                        Button { open = p } label: {
                            VStack(spacing: 2) {
                                Text(piece.text).scaledFont(24, weight: .semibold).foregroundStyle(JaColors.particle)
                                    .padding(.horizontal, 5)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(T.fn))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(JaColors.particle.opacity(0.7), lineWidth: 1.5))
                                Text(trs(Self.role(p.p))).ffFont(.caption2).foregroundStyle(T.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        VStack(spacing: 2) {
                            Text(JaInk.attributed([piece])).scaledFont(24)
                            Text(" ").ffFont(.caption2)
                        }
                    }
                }
            }
            Text(JaParticles.mapEnglish).ffFont(.footnote).foregroundStyle(T.muted)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.order, id: \.0) { r in
                    HStack(spacing: 8) {
                        Text(trs(r.0)).ffFont(.caption, .bold).foregroundStyle(T.glyph).frame(width: 92, alignment: .leading)
                        ForEach(r.1, id: \.self) { p in
                            Button { open = JaParticles.all.first { $0.p == p } } label: {
                                Text(p).scaledFont(17, weight: .semibold).foregroundStyle(JaColors.particle)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Capsule().fill(T.fn))
                                    .overlay(Capsule().stroke(T.fnEdge, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
                HStack(spacing: 8) {
                    Text(tr("動詞")).ffFont(.caption, .bold).foregroundStyle(T.glyph).frame(width: 92, alignment: .leading)
                    Text(tr("最後：動詞或形容詞，再加語尾")).ffFont(.caption).foregroundStyle(JaColors.suffix)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
    }

    static let order: [(String, [String])] = [
        ("誰／什麼", ["は", "が", "も"]), ("什麼時候", ["に", "から", "まで"]), ("在哪裡", ["で", "に"]),
        ("往哪裡", ["へ", "に", "まで"]), ("和誰", ["と"]), ("用什麼", ["で"]), ("對什麼", ["を", "に"]), ("句末", ["か", "ね", "よ"]),
    ]
    static func role(_ p: String) -> String {
        switch p {
        case "は": return "主題"
        case "が": return "主語"
        case "と": return "和誰"
        case "から": return "從"
        case "まで": return "到"
        case "で": return "用什麼"
        case "を": return "受詞"
        case "に": return "時間／目的地"
        default: return ""
        }
    }
}

struct JaParticleSheet: View {
    let p: JaParticle
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 14) {
                        Text(p.p).scaledFont(56, weight: .semibold).foregroundStyle(JaColors.particle).toneGlow()
                        PlayButton(path: "tts:" + p.p)
                        Spacer()
                    }
                    Text(trs(p.zh)).ffFont(.body).foregroundStyle(T.glyph)
                    Text(p.en).ffFont(.subheadline).foregroundStyle(T.muted)
                    ForEach(Array(p.ex.enumerated()), id: \.offset) { _, ex in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(JaInk.attributed(JaInk.marked(ex.0))).scaledFont(22).toneGlow().textSelection(.enabled)
                                Spacer(minLength: 4)
                                PlayButton(path: "tts:" + JaInk.plainText(ex.0))
                            }
                            Text(ex.1).ffFont(.subheadline).foregroundStyle(T.muted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle(tr("助詞"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: 助詞練習: a sentence missing a particle, pick it

struct JaParticleQuiz: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var q: (p: JaParticle, before: String, after: String, english: String, choices: [String])?
    @State private var picked: String?
    @State private var right = 0
    @State private var done = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let q {
                        VStack(spacing: 8) {
                            (Text(JaInk.attributed(JaInk.marked(q.before)))
                             + Text(picked == nil ? AttributedString("（　）") : JaInk.attributed([JaPiece(text: q.p.p, kind: .particle)]))
                             + Text(JaInk.attributed(JaInk.marked(q.after))))
                                .scaledFont(30).toneGlow().multilineTextAlignment(.center)
                            Text(q.english).ffFont(.subheadline).foregroundStyle(T.muted).multilineTextAlignment(.center)
                        }
                        .padding(.top, 24)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(q.choices, id: \.self) { c in
                                Button { answer(c) } label: {
                                    Text(c).scaledFont(26, weight: .semibold).foregroundStyle(ink(c))
                                        .frame(maxWidth: .infinity, minHeight: 64)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(fill(c)))
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(edge(c), lineWidth: 1.5))
                                        .contentShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(SwellButtonStyle())
                                .disabled(picked != nil)
                            }
                        }
                        .frame(maxWidth: 480)
                        if picked != nil {
                            Text(trs(q.p.zh)).ffFont(.subheadline).foregroundStyle(T.glyph).multilineTextAlignment(.center)
                            Button { next() } label: { Text(tr("下一題")).ffFont(.headline).frame(maxWidth: 260, minHeight: 30) }
                                .prominentButton(T.btnEdge)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle(tr("助詞練習"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(tr("結束")) }
                ToolbarItem(placement: .topBarTrailing) { Text("\(right) / \(done)").ffFont(.subheadline, mono: true).foregroundStyle(T.muted) }
            }
        }
        .onAppear { next() }
    }

    private func fill(_ c: String) -> Color {
        guard let p = picked, let q else { return T.fn.opacity(0.85) }
        if c == q.p.p { return T.green }
        return c == p ? T.rust : T.fn.opacity(0.6)
    }
    private func edge(_ c: String) -> Color {
        guard let p = picked, let q else { return T.fnEdge }
        if c == q.p.p { return T.greenEdge }
        return c == p ? T.rustEdge : T.fnEdge.opacity(0.5)
    }
    private func ink(_ c: String) -> Color {
        guard let p = picked, let q else { return JaColors.particle }
        if c == q.p.p { return T.greenInk }
        return c == p ? T.rustInk : T.muted
    }

    private func answer(_ c: String) {
        guard picked == nil, let q else { return }
        picked = c
        done += 1
        if c == q.p.p { right += 1 }
    }

    private func next() {
        picked = nil
        for _ in 0..<20 {
            guard let p = JaParticles.all.randomElement(), let ex = p.ex.randomElement(),
                  let r = ex.0.range(of: "[" + p.p + "]") else { continue }
            var cs = [p.p]
            for o in JaParticles.all.map(\.p).shuffled() where !cs.contains(o) && cs.count < 4 { cs.append(o) }
            q = (p, String(ex.0[..<r.lowerBound]), String(ex.0[r.upperBound...]), ex.1, cs.shuffled())
            return
        }
    }
}

// MARK: - 實驗室: put a word together on wheels, see what each part does
//
// Search a verb or adjective (日語 or English). The wheels: its stem (書か・書き・書く…), then up to three endings.
// Every wheel shows the whole word so far: what was there already in grey, the part this wheel adds in colour.

struct JaLabWord: Equatable {
    let text: String
    let reading: String
    let cls: JaClass
    let en: String
    let key: String?
    static func == (a: JaLabWord, b: JaLabWord) -> Bool { a.text == b.text && a.reading == b.reading }

    init(text: String, reading: String, cls: JaClass, en: String, key: String? = nil) {
        self.text = text; self.reading = reading; self.cls = cls; self.en = en; self.key = key
    }
    init?(_ e: ZhEntry) {
        guard case let (c, t)? = JaGrammar.classOf(e) else { return nil }
        self.init(text: t, reading: JaGrammar.readingOf(e, c), cls: c, en: JaEnglish.base(e, c), key: e.k)
    }
}

struct JaLabPage: View {
    let dict: ZhDict
    let start: ZhEntry?
    @EnvironmentObject var store: Store
    @Environment(\.horizontalSizeClass) private var hsc
    @State private var word: JaLabWord?
    @State private var query = ""
    @State private var found: [ZhEntry] = []
    @State private var task: Task<Void, Never>?
    /// each wheel's choice (0 = stop here: the word ends with its own ending, 食べ・る)
    @State private var steps = [0, 0, 0, 0, 0]

    /// quick picks when nothing is searched (the ones this dictionary has)
    static let samples = ["食べる", "書く", "行く", "飲む", "話す", "待つ", "遊ぶ", "泳ぐ", "買う", "見る", "する", "来る", "勉強", "高い", "いい", "静か"]

    /// each part added gets the next of the app's rainbow shades (not yellow and green: kanji and hiragana are those)
    static let palette: [Color] = [0xffa94d, 0x4fd8c4, 0x6eaaff, 0xc39bff, 0xff8cc6, 0xff6b6b].map { Color(hex: UInt32($0)) }
    static func partColor(_ i: Int) -> Color? { i == 0 ? nil : palette[(i - 1) % palette.count] }

    var body: some View {
        Group {
            if hsc == .regular {
                HStack(alignment: .top, spacing: 16) {
                    ScrollView { VStack(spacing: 14) { search; if let w = word { wheels(w) } }.padding() }
                        .frame(maxWidth: .infinity)
                    ScrollView { if let w = word { pane(w).padding() } }
                        .frame(maxWidth: 440)
                }
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        search
                        if let w = word {
                            wheels(w)
                            pane(w)
                        }
                    }
                    .padding()
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .navigationTitle(tr("實驗室"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
        .onAppear {
            if word == nil {
                word = start.flatMap { JaLabWord($0) } ?? Self.samples.lazy.compactMap { s in
                    (dict.byHan[s] ?? []).lazy.map { dict.entries[$0] }.compactMap { JaLabWord($0) }.first
                }.first
            }
        }
        .onChange(of: word) { steps = [0, 0, 0, 0, 0] }
        .onChange(of: query) { run() }
    }

    // MARK: choosing the word

    private var search: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(tr("查動詞或形容詞（日語、羅馬字或英文），例如：taberu、書く、eat"), text: $query)
                .scaledFont(17)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .clearButton($query)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
            if query.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Self.samples, id: \.self) { s in
                        if let e = (dict.byHan[s] ?? []).lazy.map({ dict.entries[$0] }).first(where: { JaGrammar.classOf($0) != nil }),
                           let w = JaLabWord(e) {
                            Button { word = w } label: {
                                Text(dict.hanText(e.h, e.tw, base: T.glyph)).ffFont(.subheadline, .semibold).toneGlow()
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(word == w ? T.btn : T.fn.opacity(0.8)))
                                    .overlay(Capsule().stroke(word == w ? T.btnEdge : T.fnEdge, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if found.isEmpty {
                Text(tr("沒有找到會變化的詞（動詞、形容詞）。")).ffFont(.footnote).foregroundStyle(T.muted)
            } else {
                VStack(spacing: 6) {
                    ForEach(found.prefix(12), id: \.k) { e in
                        Button {
                            word = JaLabWord(e)
                            query = ""
                        } label: {
                            ZhWordRow(dict: dict, entry: e)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func run() {
        task?.cancel()
        let q = query, d = dict
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { found = []; return }
        task = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let r: [ZhEntry] = await Task.detached(priority: .userInitiated) {
                let f = d.search(q)
                var seen = Set<Int>(), out: [ZhEntry] = []
                let order = f.englishFirst ? f.english + f.words + f.starts : f.words + f.starts + f.english
                for i in order where i < d.entries.count && seen.insert(i).inserted {
                    if JaGrammar.classOf(d.entries[i]) != nil { out.append(d.entries[i]) }
                    if out.count >= 12 { break }
                }
                return out
            }.value
            guard !Task.isCancelled else { return }
            found = r
        }
    }

    // MARK: the parts
    //
    // Each part of the word: what stays (食べ, させ, い), what changed at its end because of the part after it (書く →
    // 書か: か), and, for the last one, its own ending (る, い, す). Shown, the changed kana goes with the next part, so
    // each step reads clearly: 書・かな・い, 食べ・られ・る, 食べ・られ・な・かった, 食べ・ま・せん.

    private struct Split { var base: String; var tail: String; var ending: String }

    private static func common(_ a: String, _ b: String) -> String {
        String(zip(a, b).prefix { $0 == $1 }.map { $0.0 })
    }

    private static func splits(_ c: JaGrammar.Chain) -> [Split] {
        var out: [Split] = []
        for (i, p) in c.pieces.enumerated() {
            let pre = common(p.text, p.dict)
            var sp = Split(base: pre, tail: String(p.text.dropFirst(pre.count)), ending: "")
            // the last part, in its dictionary form: its own ending apart, the same as the ones before it change
            // (食べ・る, な・い, 高・い, ま・す), so 食べ・られ・な・い and 食べ・られ・な・かった read the same way
            if i == c.pieces.count - 1, sp.tail.isEmpty, c.cls.isVerb || c.cls.isAdj || c.cls == .masu,
               let st = JaGrammar.stem(p.text, c.cls, .i) {
                let b = common(p.text, st)
                sp.base = b
                sp.ending = String(p.text.dropFirst(b.count))
            }
            out.append(sp)
        }
        return out
    }

    /// a run of text in part i's colour (the word itself: kanji and kana in their colours)
    private static func run(_ s: String, _ i: Int) -> AttributedString {
        guard let c = partColor(i) else { return JaInk.word(s) }
        var a = AttributedString(s)
        a.foregroundColor = c
        return a
    }

    /// the word as its steps: each one the kana the step before changed (its colour) and this part (its own colour)
    private static func segments(_ c: JaGrammar.Chain) -> [AttributedString] {
        let sp = splits(c)
        var out: [AttributedString] = []
        for i in sp.indices {
            var seg = AttributedString()
            if i > 0, !sp[i - 1].tail.isEmpty { seg += run(sp[i - 1].tail, i - 1) }
            if !sp[i].base.isEmpty { seg += run(sp[i].base, i) }
            if !seg.characters.isEmpty { out.append(seg) }
        }
        if let l = sp.last {
            let n = sp.count - 1
            if !l.ending.isEmpty { out.append(run(l.ending, n)) } else if !l.tail.isEmpty { out.append(run(l.tail, n)) }
        }
        return out
    }
    private static func plainSegments(_ c: JaGrammar.Chain) -> [String] { segments(c).map { String($0.characters) } }

    /// the steps one after another (each in its own colour, nothing between them)
    private static func joined(_ segs: [AttributedString]) -> AttributedString {
        var out = AttributedString()
        for s in segs { out += s }
        return out
    }

    /// iPad: bigger wheels and text
    private var big: Bool { hsc == .regular }

    // MARK: the wheels

    /// the chain after the first k wheels (nil: a wheel before it stopped)
    private func chain(_ w: JaLabWord, upTo k: Int) -> JaGrammar.Chain? {
        var c = JaGrammar.Chain(w.text, w.cls, label: "「\(w.text)」" + trs(w.cls.name))
        for j in 0..<k {
            let opts = options(c)
            let i = min(steps[j], opts.count - 1)
            guard let s = opts[i] else { return nil }
            guard let n = c.adding(s.id) else { return nil }
            c = n
        }
        return c
    }
    /// what can come after a chain: stopping here (nil), then each ending
    private func options(_ c: JaGrammar.Chain) -> [JaGrammar.Suffix?] {
        guard c.cls != .done else { return [nil] }
        var out: [JaGrammar.Suffix?] = [nil]
        for s in c.next { out.append(s) }
        return out
    }
    /// the word as chosen on the wheels
    private func chosen(_ w: JaLabWord) -> JaGrammar.Chain {
        var last = JaGrammar.Chain(w.text, w.cls)
        for k in 0...steps.count { if let c = chain(w, upTo: k) { last = c } else { break } }
        return last
    }

    /// a wheel's row: the step this ending makes (the changed kana before it in the colour of the part it belongs to)
    private func row(_ before: JaGrammar.Chain, _ s: JaGrammar.Suffix?) -> AttributedString {
        let k = before.pieces.count
        guard let s else {
            // stopping here: the last part's own ending (る), or nothing more
            let sp = Self.splits(before)
            if let l = sp.last, !l.ending.isEmpty { return Self.run(l.ending, k - 1) }
            var a = AttributedString("—"); a.foregroundColor = T.muted; return a
        }
        guard let n = before.adding(s.id) else { return AttributedString("—") }
        let sp = Self.splits(n)
        var a = AttributedString()
        if k - 1 < sp.count, !sp[k - 1].tail.isEmpty { a += Self.run(sp[k - 1].tail, k - 1) }
        if k < sp.count {
            a += Self.run(sp[k].base.isEmpty && sp[k].ending.isEmpty ? (n.pieces[k].text.isEmpty ? "∅" : n.pieces[k].text) : sp[k].base, k)
        }
        return a.characters.isEmpty ? AttributedString("∅") : a
    }

    private func wheel(_ k: Int, _ before: JaGrammar.Chain) -> some View {
        let opts = options(before)
        return VStack(spacing: 4) {
            Text(tr("接 \(k + 1)")).ffFont(big ? .footnote : .caption2, .bold).foregroundStyle(T.muted)
            LabWheel(count: opts.count, selection: Binding(get: { min(steps[k], opts.count - 1) }, set: { v in
                // (the wheels after it and the word glide to their new places instead of jumping)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    steps[k] = v
                    for j in (k + 1)..<steps.count { steps[j] = 0 }
                }
            }), rowHeight: big ? 72 : 46, height: big ? 300 : 170) { i in
                VStack(spacing: big ? 2 : 0) {
                    Text(row(before, opts[i])).scaledFont(big ? 32 : 20, weight: .semibold).toneGlow().lineLimit(1).minimumScaleFactor(0.5)
                    Text(opts[i].map { trs($0.name) } ?? (Self.splits(before).last?.ending.isEmpty == false ? trs("辭書形") : trs("到這裡")))
                        .font(.system(size: big ? 13 : 10)).foregroundStyle(T.muted).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func wheels(_ w: JaLabWord) -> some View {
        let base = JaGrammar.Chain(w.text, w.cls)
        let first = Self.splits(base).first
        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 4) {
                // the word's part that stays (食べ, 書): not on a wheel
                VStack(spacing: 4) {
                    Text(tr("詞")).ffFont(big ? .footnote : .caption2, .bold).foregroundStyle(T.muted)
                    Text(JaInk.word(first?.base.isEmpty == false ? first!.base : w.text)).scaledFont(big ? 34 : 22, weight: .semibold).toneGlow()
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(height: big ? 300 : 170)
                }
                .frame(minWidth: big ? 64 : 44)
                ForEach(0..<steps.count, id: \.self) { k in
                    if let before = chain(w, upTo: k), k == 0 || steps[k - 1] > 0, options(before).count > 1 {
                        // a new wheel slides in from the side; one that's no longer needed fades away
                        wheel(k, before)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .opacity.combined(with: .scale(scale: 0.9))))
                    }
                }
            }
            Text(tr("一個滾輪接一個部分，每一部分一個顏色。最後一個音節會變的話，它跟著下一個部分出現（書 ＋ かな ＋ い）。"))
                .ffFont(.caption).foregroundStyle(T.muted).multilineTextAlignment(.center)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
    }

    // MARK: what it means

    private func pane(_ w: JaLabWord) -> some View {
        let c = chosen(w)
        let reading = w.reading == w.text ? nil : JaGrammar.Chain(w.reading, w.cls).adding(c.ops)
        let readSegs = Self.plainSegments(reading ?? c)
        let en = w.en.hasPrefix("be ") || !(w.cls.isAdj || w.cls == .adjNa) ? w.en : "be " + w.en
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 12) {
                    Text(Self.joined(Self.segments(c))).scaledFont(big ? 48 : 36, weight: .semibold).toneGlow()
                        .contentTransition(.interpolate)
                        .lineLimit(1).minimumScaleFactor(0.4).textSelection(.enabled)
                    PlayButton(path: "tts:" + (reading?.text ?? c.text))
                    Spacer(minLength: 0)
                }
                if let r = reading { Text(Self.joined(Self.segments(r))).scaledFont(big ? 22 : 18).toneGlow() }
                // rōmaji, a hyphen between the parts: tabe-rare-ru
                Text(readSegs.map { JaKana.romaji($0) }.joined(separator: "-")).latFont(17).foregroundStyle(T.greenInk)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Chip(text: tr("英"), fill: T.fn, edge: T.fnEdge, ink: T.muted)
                    Text(JaEnglish.compose(en, c.ops)).ffFont(.body, .semibold).foregroundStyle(T.glyph)
                }
                Text(tr("（英文是依規則組合出來的大意）")).ffFont(.caption2).foregroundStyle(T.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("每一部分")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                ForEach(Array(c.pieces.enumerated()), id: \.offset) { n, p in
                    HStack(alignment: .top, spacing: 12) {
                        Text(p.text.isEmpty ? AttributedString("∅") : Self.run(p.text, n)).scaledFont(24, weight: .semibold).toneGlow()
                            .frame(minWidth: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle().fill(Self.partColor(n) ?? JaColors.kanji).frame(width: 8, height: 8)
                                Text(trs(p.label)).ffFont(.subheadline, .bold).foregroundStyle(Self.partColor(n) ?? T.glyph)
                            }
                            if !p.note.isEmpty { Text(p.note).ffFont(.footnote).foregroundStyle(T.muted) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(T.fn.opacity(0.7)))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
            if let k = w.key, let e = dict.entry(k) {
                NavigationLink(value: ZhKey(k: e.k)) { TileLabel(icon: "character.book.closed", title: tr("在詞典看「\(e.h)」")) }
                    .buttonStyle(.plain)
            }
        }
    }
}


/// a wheel to pick from, any size (the system's wheel has rows too low for big text): rows snap to the middle, tap one
/// to go to it
struct LabWheel<Row: View>: View {
    let count: Int
    @Binding var selection: Int
    let rowHeight: CGFloat
    let height: CGFloat
    @ViewBuilder let row: (Int) -> Row
    @State private var pos: Int?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    row(i)
                        .opacity(i == selection ? 1 : 0.55)
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.snappy) { pos = i } }
                        .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $pos, anchor: .center)
        .contentMargins(.vertical, max(0, (height - rowHeight) / 2), for: .scrollContent)
        .frame(height: height)
        // the row chosen: a band across the middle
        .background(
            RoundedRectangle(cornerRadius: 12).fill(T.btn.opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.btnEdge.opacity(0.7), lineWidth: 1.5))
                .frame(height: rowHeight)
        )
        // the rows fade out at the top and the bottom
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                     .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .sensoryFeedback(.selection, trigger: pos)
        .onAppear { pos = selection }
        .onChange(of: pos) { if let p = pos, p != selection, p < count { selection = p } }
        .onChange(of: selection) { if pos != selection { pos = selection } }
        .onChange(of: count) { if selection >= count { selection = max(0, count - 1) }; pos = min(selection, max(0, count - 1)) }
    }
}
