import SwiftUI

/// 設定 → 選聲調顏色: pick the colour of each tone, for 台語, 華語, 粵語 and 客語, from a grid of balls
/// (one column per colour in rainbow order, light at the top and dark at the bottom); for 日語, the colours of kanji,
/// hiragana, katakana, particles and suffixes, from the same balls
struct ToneColorPicker: View {
    @EnvironmentObject var store: Store
    @AppStorage(ToneColors.versionKey) private var version = 0
    @AppStorage(ToneColors.key) private var toneSys = 0
    /// whose colours: 0 台語, 1 華語, 2 粵語, 3 客語, 4 日語
    @State private var which: Int
    @State private var selected: Int
    /// (日語's colours changed: drawn again)
    @State private var jaVersion = 0

    init(set start: Int? = nil) {
        let s = min(max(start ?? Lang.current, 0), 4)
        _which = State(initialValue: s)
        _selected = State(initialValue: s == 4 ? 0 : 1)
    }

    private var tones: [Int] { which == 4 ? Array(0..<JaColors.keys.count) : ToneColors.tones(set: which) }

    /// a tone's colour (日語: a kind of text's)
    private func hexOf(_ t: Int) -> UInt32 {
        which == 4 ? UInt32(truncatingIfNeeded: JaColors.hex(t)) : ToneColors.hex(set: which, t)
    }
    private func pick(_ t: Int, _ hex: UInt32) {
        if which == 4 {
            UserDefaults.standard.set(Int(hex & 0xFFFFFF), forKey: JaColors.keys[t])
            jaVersion += 1
        } else {
            ToneColors.set(set: which, t, hex)
        }
    }

    private func name(_ t: Int) -> String {
        if which == 4 { return trs(JaColors.names[t]) }
        if which == 1 { return t == 0 ? trs("輕聲") : ["", trs("一聲"), trs("二聲"), trs("三聲"), trs("四聲")][t] }
        if which == 3 { return trs([1: "陰平", 2: "上聲", 3: "去聲", 4: "陰入", 5: "陽平", 7: "陽去", 8: "陽入"][t] ?? "") }
        return t == 0 ? trs("輕聲") : tr("第 \(t) 聲")
    }

    /// the tones that already use a colour
    private func users(_ hex: UInt32) -> [Int] { tones.filter { hexOf($0) == hex } }

    var body: some View {
        let _ = (version, jaVersion)
        Form {
            Section {
                Picker("", selection: $which) {
                    Text(tr("台語")).tag(0)
                    Text(tr("華語")).tag(1)
                    Text(tr("粵語")).tag(2)
                    Text(tr("客語")).tag(3)
                    Text(tr("日語")).tag(4)
                }
                .pickerStyle(.segmented)
                .onChange(of: which) { selected = which == 4 ? 0 : 1 }
            }
            .listRowBackground(Color.clear)

            Section {
                // the tones: tap one, then tap a ball below
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: which == 2 ? 6 : (which == 3 ? 4 : 5)), spacing: 10) {
                    ForEach(tones, id: \.self) { t in
                        let on = selected == t
                        Button { withAnimation(.snappy) { selected = t } } label: {
                            VStack(spacing: 4) {
                                Circle().fill(Color(hex: hexOf(t)))
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(on ? T.glyph : Color.clear, lineWidth: 2.5).padding(-4))
                                Text(name(t)).ffFont(.caption, on ? Font.Weight.bold : Font.Weight.regular).foregroundStyle(on ? T.glyph : T.muted)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name(t))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(which == 4 ? tr("文字（點一個，再點下面的顏色）") : tr("聲調（點一個，再點下面的顏色）"))
            } footer: {
                if which == 0 && toneSys == 5 { Text(tr("五聲：第 8 聲用第 1 聲的顏色，第 4 聲用第 3 聲的顏色。")) }
                if which == 3 { Text(tr("客語的聲調照類別上色：同一個類別在各腔的調值不一樣，顏色一樣（例如陰平在四縣是 24，在海陸是 53）。")) }
            }
            .listRowBackground(T.fn.opacity(0.7))

            Section {
                let cols = ToneColors.palette
                Grid(horizontalSpacing: 4, verticalSpacing: 8) {
                    ForEach(0..<5, id: \.self) { row in
                        GridRow {
                            ForEach(cols.indices, id: \.self) { c in
                                ball(cols[c].shades[row], label: cols[c].name)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } header: {
                Text(tr("\(name(selected))的顏色"))
            } footer: {
                Text(which == 4 ? tr("中間那一排是原本的顏色，往上越淺，往下越深。球裡的數字是已經用這個顏色的文字（1 漢字、2 平假名、3 片假名、4 助詞、5 語尾）。")
                     : tr("中間那一排是原本的顏色，往上越淺，往下越深。球裡的數字是已經用這個顏色的聲調。"))
            }
            .listRowBackground(T.fn.opacity(0.7))

            Section {
                sample
            } header: {
                Text(tr("看起來"))
            }
            .listRowBackground(T.fn.opacity(0.7))

            Section {
                Button(tr("恢復原本的顏色（\(trs(Lang.names[which]))）")) {
                    if which == 4 {
                        for k in JaColors.keys { UserDefaults.standard.removeObject(forKey: k) }
                        jaVersion += 1
                    } else {
                        ToneColors.resetAll(set: which)
                    }
                }
                    .foregroundStyle(T.rustInk)
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(which == 4 ? tr("日語的顏色") : tr("選聲調顏色"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ball(_ hex: UInt32, label: String) -> some View {
        let picked = hexOf(selected) == hex
        let who = users(hex)
        return Button {
            withAnimation(.snappy) { pick(selected, hex) }
        } label: {
            Circle().fill(Color(hex: hex))
                .frame(width: 27, height: 27)
                .shadow(color: Color(hex: hex).opacity(0.55), radius: picked ? 6 : 0)
                .overlay(Circle().stroke(picked ? T.glyph : Color.clear, lineWidth: 2.5).padding(-3))
                .overlay {
                    if !who.isEmpty {
                        Text(who.map { which == 4 ? String($0 + 1) : ($0 == 0 ? trs("輕") : String($0)) }.joined(separator: ""))
                            .font(.system(size: who.count > 1 ? 9 : 12, weight: .bold))
                            .foregroundStyle(.black.opacity(0.7))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(2)
                    }
                }
                .frame(width: 31, height: 31)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// every tone in its colour, on a word
    @ViewBuilder private var sample: some View {
        if which == 4 {
            // a sentence with every kind: kanji, hiragana, katakana, particles, a suffix
            Text(JaInk.attributed(JaInk.marked("猫[が]ミルク[を]飲み{ます}。"))).scaledFont(28)
                .frame(maxWidth: .infinity)
                .id(jaVersion)
        } else if which == 3 {
            // 分 粉 糞 忽 焚 份 佛: fun / fud in each tone category (四縣; 陽去 is 海陸's)
            HStack(spacing: 0) {
                ForEach(Array(zip(["分", "粉", "糞", "忽", "焚", "份", "佛"],
                                  ["funˊ", "funˋ", "fun", "fudˋ", "funˇ", "fun+", "fud"]).enumerated()), id: \.offset) { i, p in
                    let t = ToneColors.hakTones[i]
                    let c = Color(hex: ToneColors.hex(set: 3, t))
                    VStack(spacing: 2) {
                        Text("\(t)").ffFont(.caption2, .bold).foregroundStyle(T.muted)
                        Text(p.0).scaledFont(24, weight: .semibold).foregroundStyle(c)
                        Text(p.1).latFont(13).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        } else if which == 2 {
            // 詩 史 試 時 市 事: si1–si6
            HStack(spacing: 14) {
                ForEach(Array(zip(["詩", "史", "試", "時", "市", "事"], [1, 2, 3, 4, 5, 6])), id: \.0) { h, t in
                    let c = Color(hex: ToneColors.hex(set: 2, t))
                    VStack(spacing: 2) {
                        Text(h).scaledFont(26, weight: .semibold).foregroundStyle(c)
                        Text("si\(t)").latFont(15).foregroundStyle(c)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } else if which == 1 {
            // 媽 麻 馬 罵 嗎
            HStack(spacing: 14) {
                ForEach(Array(zip(["媽", "麻", "馬", "罵", "嗎"], [1, 2, 3, 4, 0])), id: \.0) { h, t in
                    VStack(spacing: 2) {
                        Text(h).scaledFont(26, weight: .semibold).foregroundStyle(Color(hex: ToneColors.hex(zh: true, t)))
                        Text(["mā", "má", "mǎ", "mà", "ma"][t == 0 ? 4 : t - 1]).latFont(15).foregroundStyle(Color(hex: ToneColors.hex(zh: true, t)))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            // 番 返 販 法 凡 犯 泛 罰 蕃: tones 1–8 and the light tone, in 皓羅
            HStack(spacing: 0) {
                ForEach(Array(zip(["番", "返", "販", "法", "凡", "犯", "泛", "罰", "蕃"],
                                  ["hua̍n", "huàn", "huạn", "huạt", "huán", "hua̱n", "huān", "hua̍t", "--huan"]).enumerated()), id: \.offset) { i, p in
                    let t = ToneColors.twTones[i]
                    let c = Color(hex: ToneColors.hex(zh: false, t))
                    VStack(spacing: 2) {
                        Text(t == 0 ? trs("輕") : "\(t)").ffFont(.caption2, .bold).foregroundStyle(T.muted)
                        Text(p.0).scaledFont(22, weight: .semibold).foregroundStyle(c)
                        Text(p.1).latFont(11).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
