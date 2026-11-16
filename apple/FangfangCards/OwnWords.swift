import SwiftUI

/// purple 「自訂」 label: a word you added yourself, not from the MOE dictionary
struct OwnChip: View {
    var body: some View { Chip(text: tr("自訂"), fill: T.own, edge: T.ownEdge, ink: T.ownInk) }
}

/// 詞典 → 自訂: the words you added yourself
struct OwnPane: View {
    let dict: Dict
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @State private var adding = false
    @State private var picking = false
    @State private var csv: CsvFile?
    @State private var message: String?

    var body: some View {
        let keys = store.ownKeys
        List {
            Section {
                Button { adding = true } label: {
                    Label(tr("加一個詞"), systemImage: "plus.circle.fill")
                        .ffFont(.headline).foregroundStyle(T.ownInk)
                }
                Button { picking = true } label: {
                    Label(tr("從 CSV 檔加入"), systemImage: "tablecells")
                        .ffFont(.headline).foregroundStyle(T.ownInk)
                }
                if let message {
                    Text(message).ffFont(.footnote).foregroundStyle(T.muted)
                }
            } footer: {
                Text(tr("自己加的詞不是教育部辭典的內容，在「轉換」和「詞典」都會用紫色和「自訂」標示。CSV 檔：一行一個詞，漢字和讀音一定要有，意思和例句可以有；加入之前可以選哪一欄是什麼。"))
            }
            .listRowBackground(T.fn.opacity(0.7))
            if !keys.isEmpty {
                Section {
                    ForEach(keys, id: \.self) { k in
                        NavigationLink(value: DictKey(k: k)) { row(k) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { withAnimation { store.removeOwn(k) } } label: {
                                    Label(tr("刪除"), systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text(tr("\(keys.count) 個詞（往左滑刪除）"))
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $adding) {
            AddOwnWordSheet(dict: dict).environmentObject(store)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let text = CsvText.decode(data) else { message = trs("讀不到這個檔案。"); return }
            let rows = CsvText.rows(text)
            if rows.isEmpty { message = trs("這個檔案是空的。"); return }
            message = nil
            csv = CsvFile(name: url.lastPathComponent, rows: rows)
        }
        .sheet(item: $csv) { f in
            CsvImportSheet(dict: dict, file: f) { n in message = tr("加入了 \(n) 個詞。") }.environmentObject(store)
        }
    }

    private func row(_ k: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Dict.hanOf(k)).scaledFont(20, weight: .semibold).foregroundStyle(T.ownInk)
            Text(dict.codes(Dict.codesOf(k), TwRom.lat(rom), -1)).latFont(16).foregroundStyle(T.greenInk)
            Text(dict.codes(Dict.codesOf(k), 3, -1)).ffFont(.footnote).foregroundStyle(T.purpleInk).hongimLine()
            // (its meaning, if you gave it one)
            let m = store.ownInfo(k).meaning
            if !m.isEmpty { Text(m).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(1) }
            Spacer(minLength: 0)
            OwnChip()
        }
    }
}

/// add a word: 漢字 and its reading (typed in 皓羅, 台羅, 白話字 or 方音)
struct AddOwnWordSheet: View {
    let dict: Dict
    var han0 = ""
    var reading0 = ""
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @State private var han = ""
    @State private var reading = ""
    @State private var meaning = ""
    @State private var example = ""
    @State private var engine: ConvertEngine?

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("漢字")) {
                    TextField(tr("例：揣頭路"), text: $han)
                        .autocorrectionDisabled()
                        .clearButton($han)
                }
                Section {
                    TextField(tr("例：tshuē-thâu-lōo"), text: $reading)
                        .latFont(17)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .clearButton($reading)
                } header: {
                    Text(tr("讀音"))
                } footer: {
                    Text(tr("用皓羅、台羅、白話字或方音都可以。寫聲調比較準；沒寫聲調的話，請看下面的結果對不對。"))
                }
                Section {
                    TextField(tr("意思（可以不寫）"), text: $meaning, axis: .vertical)
                    TextField(tr("例句（可以不寫）"), text: $example, axis: .vertical)
                } header: {
                    Text(tr("意思和例句"))
                }
                Section(tr("結果")) {
                    switch check {
                    case .ok(let codes):
                        let cs = codes.joined(separator: " ")
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(han.trimmingCharacters(in: .whitespaces)).scaledFont(24, weight: .semibold).foregroundStyle(T.ownInk)
                            OwnChip()
                        }
                        Text(dict.codes(cs, 0, -1)).latFont(17).foregroundStyle(T.greenInk)
                        Text(dict.codes(cs, 1, -1) + "　" + dict.codes(cs, 2, -1)).latFont(14).foregroundStyle(T.greenInk.opacity(0.8))
                        Text(dict.codes(cs, 3, -1)).foregroundStyle(T.purpleInk)
                    case .problem(let msg):
                        Text(msg).ffFont(.footnote).foregroundStyle(T.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(tr("加一個詞"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("加入")) {
                        if case .ok(let codes) = check {
                            store.addOwn(han.trimmingCharacters(in: .whitespaces) + "\t" + codes.joined(separator: " "), meaning: meaning, example: example)
                            dismiss()
                        }
                    }
                    .disabled({ if case .ok = check { return false }; return true }())
                }
            }
            .onAppear {
                if han.isEmpty { han = han0 }
                if reading.isEmpty { reading = reading0 }
                if engine == nil { engine = ConvertEngine(dict: dict) }
            }
        }
    }

    private enum Check { case ok([String]), problem(String) }

    /// the reading as syllable codes, one per 漢字 (the same check as a CSV file's words)
    private var check: Check {
        guard let engine else { return .problem("") }
        switch OwnWordCheck.check(han: han, reading: reading, engine: engine, dict: dict, store: store) {
        case .ok(let c): return .ok(c)
        case .problem(let p): return .problem(p)
        }
    }
}
