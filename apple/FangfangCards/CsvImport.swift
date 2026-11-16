import SwiftUI
import UniformTypeIdentifiers

// 詞典 → 自訂 → 從 CSV 檔加入: many of your own 台語 words at once, from a CSV (or tab-separated) file. You say which
// column has what: 漢字 and 讀音 (needed), and the meaning and an example sentence (if the file has them).

/// a CSV / TSV file's rows: commas, tabs or semicolons (whichever the first lines use most), quotes as in Excel
enum CsvText {
    static func decode(_ data: Data) -> String? {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        if let s = String(data: d, encoding: .utf8) { return s }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16) { return s }
        // (an older file from Excel on a Taiwanese computer)
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)))
        return String(data: data, encoding: big5)
    }

    static func rows(_ text: String) -> [[String]] {
        let head = text.prefix(4000)
        let seps: [Character] = [",", "\t", ";"]
        let sep = seps.max { a, b in head.filter { $0 == a }.count < head.filter { $0 == b }.count } ?? ","
        var rows: [[String]] = [], row: [String] = [], cell = ""
        var quoted = false
        var it = Array(text)
        if it.last != "\n" { it.append("\n") }
        var i = 0
        while i < it.count {
            let c = it[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < it.count, it[i + 1] == "\"" { cell.append("\""); i += 1 } else { quoted = false }
                } else { cell.append(c) }
            } else if c == "\"" && cell.isEmpty {
                quoted = true
            } else if c == sep {
                row.append(cell); cell = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(cell); cell = ""
                if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []
            } else {
                cell.append(c)
            }
            i += 1
        }
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
    }
}

/// one word of your own: its 漢字 and reading → the reading's syllables (the same rules as 加一個詞)
/// (on the main thread, as the list of your words is)
@MainActor
enum OwnWordCheck {
    enum Result { case ok([String]), problem(String) }

    static func check(han hanIn: String, reading: String, engine: ConvertEngine, dict: Dict, store: Store) -> Result {
        let h = hanIn.trimmingCharacters(in: .whitespaces)
        let chars = h.unicodeScalars.filter { ConvertEngine.isHan($0.value) }
        if h.isEmpty { return .problem(trs("先寫漢字。")) }
        if chars.count != h.unicodeScalars.count { return .problem(trs("漢字欄只能寫漢字。")) }
        if reading.trimmingCharacters(in: .whitespaces).isEmpty { return .problem(trs("再寫讀音。")) }
        var codes: [String] = []
        for it in engine.convert(reading).items {
            if it.space || it.newline { continue }
            if let raw = it.raw {
                if raw.trimmingCharacters(in: CharacterSet(charactersIn: " -‑–")).isEmpty { continue }
                return .problem(tr("看不懂「\(raw)」這個讀音。"))
            }
            guard let c = it.current.codes else { return .problem(trs("看不懂這個讀音。")) }
            codes += c
        }
        if codes.isEmpty { return .problem(trs("看不懂這個讀音。")) }
        if codes.count != chars.count { return .problem(tr("讀音有 \(codes.count) 個音節，漢字有 \(chars.count) 個字，要一樣多。")) }
        let key = h + "\t" + codes.joined(separator: " ")
        if dict.baseKeys.contains(key) || (dict.altParent[key] != nil) { return .problem(trs("辭典裡已經有這個詞了。")) }
        if store.isOwn(key) { return .problem(trs("這個詞已經在「自訂」裡了。")) }
        return .ok(codes)
    }

    /// the reading looks like it's written in this spelling (0 皓羅, 1 台羅, 2 白話字, 3 方音): the letters the same
    /// as the app writes them, the tones and hyphens aside
    static func looksLike(_ reading: String, codes: [String], system: Int, dict: Dict) -> Bool {
        func plain(_ s: String) -> String {
            s.decomposedStringWithCanonicalMapping.unicodeScalars
                .filter { !(0x300...0x36F).contains($0.value) && !CharacterSet.decimalDigits.contains($0) && !" -‑–".unicodeScalars.contains($0) }
                .map(String.init).joined().lowercased()
        }
        return plain(reading) == plain(dict.codes(codes.joined(separator: " "), system, -1))
    }
}

/// a file chosen to read words from
struct CsvFile: Identifiable {
    let id = UUID()
    let name: String
    let rows: [[String]]
}

/// which column has what, a look at the result, and 加入
struct CsvImportSheet: View {
    let dict: Dict
    let file: CsvFile
    var onDone: (Int) -> Void = { _ in }
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var header = true
    @State private var colHan = 0
    @State private var colReading = 1
    @State private var colMeaning = -1
    @State private var colExample = -1
    /// the reading's spelling: -1 any (each reading as it's written), 0 皓羅, 1 台羅, 2 白話字, 3 方音
    @State private var system = -1
    @State private var engine: ConvertEngine?
    @State private var results: [Row] = []
    @State private var ready = false

    struct Row: Identifiable {
        let id: Int             // the line in the file (1 = the first)
        let han: String
        let codes: [String]?
        let problem: String
        let meaning: String
        let example: String
        let unlike: Bool        // not in the chosen spelling
    }

    private var columns: Int { file.rows.map(\.count).max() ?? 0 }
    private var dataRows: ArraySlice<[String]> { header ? file.rows.dropFirst() : file.rows[...] }
    private var good: [Row] { results.filter { $0.codes != nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(tr("檔案"), value: file.name)
                    LabeledContent(tr("行數"), value: "\(dataRows.count)")
                    Toggle(tr("第一行是標題"), isOn: $header)
                }
                Section {
                    columnPicker(tr("漢字"), $colHan, optional: false)
                    columnPicker(tr("讀音"), $colReading, optional: false)
                    Picker(tr("讀音的寫法"), selection: $system) {
                        Text(tr("自動（每個讀音照它的寫法讀）")).tag(-1)
                        Text(tr("皓羅")).tag(0)
                        Text(tr("台羅")).tag(1)
                        Text(tr("白話字")).tag(2)
                        Text(tr("方音")).tag(3)
                    }
                    columnPicker(tr("意思"), $colMeaning, optional: true)
                    columnPicker(tr("例句"), $colExample, optional: true)
                } header: {
                    Text(tr("哪一欄是什麼"))
                } footer: {
                    Text(tr("漢字和讀音一定要有；意思和例句可以沒有。讀音用皓羅、台羅、白話字或方音都可以，聲調寫符號或數字都可以。選了寫法的話，不像那種寫法的讀音會標出來，請看一下對不對。"))
                }
                Section {
                    if !ready {
                        ProgressView()
                    } else {
                        Text(tr("可以加入 \(good.count) 個詞") + (results.count > good.count ? tr("；\(results.count - good.count) 行沒辦法加入") : ""))
                            .ffFont(.headline)
                        ForEach(results.prefix(60)) { r in resultRow(r) }
                        if results.count > 60 {
                            Text(tr("（只列出前 60 行）")).ffFont(.footnote).foregroundStyle(T.muted)
                        }
                    }
                } header: {
                    Text(tr("結果"))
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(tr("從 CSV 檔加入"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("加入 \(good.count) 個")) {
                        store.addOwn(good.map { (key: $0.han + "\t" + ($0.codes ?? []).joined(separator: " "), meaning: $0.meaning, example: $0.example) })
                        onDone(good.count)
                        dismiss()
                    }
                    .disabled(!ready || good.isEmpty)
                }
            }
            .onAppear {
                if engine == nil { engine = ConvertEngine(dict: dict) }
                guess()
            }
            .task(id: "\(header)|\(colHan)|\(colReading)|\(colMeaning)|\(colExample)|\(system)") {
                ready = false
                await Task.yield()
                results = check()
                ready = true
            }
        }
    }

    private func columnPicker(_ title: String, _ sel: Binding<Int>, optional: Bool) -> some View {
        Picker(title, selection: sel) {
            if optional { Text(tr("沒有")).tag(-1) }
            ForEach(0..<columns, id: \.self) { c in
                Text(tr("第 \(c + 1) 欄") + sample(c)).tag(c)
            }
        }
    }

    /// what the column has in its first line (the title, or the first word)
    private func sample(_ c: Int) -> String {
        guard let r = file.rows.first, c < r.count, !r[c].isEmpty else { return "" }
        let s = r[c]
        return "：" + (s.count > 14 ? String(s.prefix(14)) + "…" : s)
    }

    @ViewBuilder private func resultRow(_ r: Row) -> some View {
        if let codes = r.codes {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(r.han).scaledFont(19, weight: .semibold).foregroundStyle(T.ownInk)
                    Text(dict.codes(codes.joined(separator: " "), 0, -1)).latFont(15).foregroundStyle(T.greenInk)
                    Text(dict.codes(codes.joined(separator: " "), 3, -1)).ffFont(.footnote).foregroundStyle(T.purpleInk)
                }
                if !r.meaning.isEmpty { Text(r.meaning).ffFont(.footnote).foregroundStyle(T.glyph.opacity(0.8)).lineLimit(2) }
                if !r.example.isEmpty { Text(trs("例：") + r.example).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(2) }
                if r.unlike { Text(tr("第 \(r.id) 行：讀音不像選的寫法，請看一下對不對。")).ffFont(.caption).foregroundStyle(T.rustInk) }
            }
        } else {
            Text(tr("第 \(r.id) 行") + (r.han.isEmpty ? "" : "「\(r.han)」") + "：" + r.problem)
                .ffFont(.footnote).foregroundStyle(T.rustInk)
        }
    }

    /// a first guess: a title line or not, and which column has the 漢字, the reading and the meaning
    private func guess() {
        guard let first = file.rows.first, columns > 0 else { return }
        func isHan(_ s: String) -> Bool {
            !s.isEmpty && s.unicodeScalars.allSatisfy { ConvertEngine.isHan($0.value) }
        }
        func isReading(_ s: String) -> Bool {
            !s.isEmpty && s.unicodeScalars.allSatisfy { $0.isASCII || (0x300...0x36F).contains($0.value) || (0x3100...0x31BF).contains($0.value) || $0.properties.isAlphabetic && !ConvertEngine.isHan($0.value) }
                && s.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        }
        let body = Array(file.rows.dropFirst().prefix(30))
        func share(_ c: Int, _ f: (String) -> Bool) -> Double {
            let xs = body.compactMap { c < $0.count ? $0[c] : nil }
            return xs.isEmpty ? 0 : Double(xs.filter(f).count) / Double(xs.count)
        }
        let hanCol = (0..<columns).max { share($0, isHan) < share($1, isHan) } ?? 0
        let readCol = (0..<columns).filter { $0 != hanCol }.max { share($0, isReading) < share($1, isReading) } ?? min(1, columns - 1)
        colHan = hanCol
        colReading = readCol
        colMeaning = (0..<columns).first { $0 != hanCol && $0 != readCol } ?? -1
        colExample = -1
        // (a file this app exported, or one with its columns named: the meaning and example columns by their names)
        let names = first.map { $0.lowercased() }
        if let m = names.firstIndex(where: { $0 == "meaning" || $0 == "意思" }), m != hanCol, m != readCol { colMeaning = m }
        if let x = names.firstIndex(where: { $0 == "example" || $0 == "例句" }), x != hanCol, x != readCol, x != colMeaning { colExample = x }
        // (a title line: its 漢字 column isn't a word like the others)
        header = hanCol < first.count && !isHan(first[hanCol]) || (readCol < first.count && !isReading(first[readCol]))
    }

    private func check() -> [Row] {
        guard let engine else { return [] }
        var out: [Row] = [], seen = Set<String>()
        let offset = header ? 2 : 1
        for (i, r) in dataRows.enumerated() {
            func at(_ c: Int) -> String { c >= 0 && c < r.count ? r[c] : "" }
            let han = at(colHan), reading = at(colReading)
            switch OwnWordCheck.check(han: han, reading: reading, engine: engine, dict: dict, store: store) {
            case .ok(let codes):
                let key = han + "\t" + codes.joined(separator: " ")
                if !seen.insert(key).inserted {
                    out.append(Row(id: i + offset, han: han, codes: nil, problem: trs("檔案裡已經有這個詞了。"), meaning: "", example: "", unlike: false))
                    continue
                }
                let unlike = system >= 0 && !OwnWordCheck.looksLike(reading, codes: codes, system: system, dict: dict)
                out.append(Row(id: i + offset, han: han, codes: codes, problem: "", meaning: at(colMeaning), example: at(colExample), unlike: unlike))
            case .problem(let p):
                out.append(Row(id: i + offset, han: han, codes: nil, problem: p, meaning: "", example: "", unlike: false))
            }
        }
        return out
    }
}
