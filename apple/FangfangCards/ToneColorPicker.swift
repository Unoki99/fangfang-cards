import SwiftUI

/// 設定 → 選聲調顏色: pick the colour of each tone, for 台語, 華語 and 粵語, from a grid of balls
/// (one column per colour in rainbow order, light at the top and dark at the bottom)
struct ToneColorPicker: View {
    @EnvironmentObject var store: Store
    @AppStorage(ToneColors.versionKey) private var version = 0
    @AppStorage(ToneColors.key) private var toneSys = 0
    /// whose colours: 0 台語, 1 華語, 2 粵語
    @State private var set = Lang.current
    @State private var selected = 1

    private var tones: [Int] { ToneColors.tones(set: set) }

    private func name(_ t: Int) -> String {
        if set == 1 { return t == 0 ? trs("輕聲") : ["", trs("一聲"), trs("二聲"), trs("三聲"), trs("四聲")][t] }
        return t == 0 ? trs("輕聲") : tr("第 \(t) 聲")
    }

    /// the tones that already use a colour
    private func users(_ hex: UInt32) -> [Int] { tones.filter { ToneColors.hex(set: set, $0) == hex } }

    var body: some View {
        let _ = version
        Form {
            Section {
                Picker("", selection: $set) {
                    Text(tr("台語")).tag(0)
                    Text(tr("華語")).tag(1)
                    Text(tr("粵語")).tag(2)
                }
                .pickerStyle(.segmented)
                .onChange(of: set) { selected = 1 }
            }
            .listRowBackground(Color.clear)

            Section {
                // the tones: tap one, then tap a ball below
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: set == 2 ? 6 : 5), spacing: 10) {
                    ForEach(tones, id: \.self) { t in
                        let on = selected == t
                        Button { withAnimation(.snappy) { selected = t } } label: {
                            VStack(spacing: 4) {
                                Circle().fill(Color(hex: ToneColors.hex(set: set, t)))
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
                Text(tr("聲調（點一個，再點下面的顏色）"))
            } footer: {
                if set == 0 && toneSys == 5 { Text(tr("五聲：第 8 聲用第 1 聲的顏色，第 4 聲用第 3 聲的顏色。")) }
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
                Text(tr("中間那一排是原本的顏色，往上越淺，往下越深。球裡的數字是已經用這個顏色的聲調。"))
            }
            .listRowBackground(T.fn.opacity(0.7))

            Section {
                sample
            } header: {
                Text(tr("看起來"))
            }
            .listRowBackground(T.fn.opacity(0.7))

            Section {
                Button(tr("恢復原本的顏色（\(trs(Lang.names[set]))）")) { ToneColors.resetAll(set: set) }
                    .foregroundStyle(T.rustInk)
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("選聲調顏色"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ball(_ hex: UInt32, label: String) -> some View {
        let picked = ToneColors.hex(set: set, selected) == hex
        let who = users(hex)
        return Button {
            withAnimation(.snappy) { ToneColors.set(set: set, selected, hex) }
        } label: {
            Circle().fill(Color(hex: hex))
                .frame(width: 27, height: 27)
                .shadow(color: Color(hex: hex).opacity(0.55), radius: picked ? 6 : 0)
                .overlay(Circle().stroke(picked ? T.glyph : Color.clear, lineWidth: 2.5).padding(-3))
                .overlay {
                    if !who.isEmpty {
                        Text(who.map { $0 == 0 ? trs("輕") : String($0) }.joined(separator: ""))
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
        if set == 2 {
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
        } else if set == 1 {
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
