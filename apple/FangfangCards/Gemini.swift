import SwiftUI

// MARK: - Gemini (your own API key, 設定 → 詞典 → Gemini)
//
// Only used when you turn it on and give it your own key (from Google AI Studio): nothing is sent anywhere otherwise.
// 1. A dictionary search that finds nothing asks it for the words you most likely meant (Chinese words; 日語 and 瑞典語:
//    words of that language), shown as the dictionary's words. 華語: a Chinese term it knows can be added to 自訂.
// 2. 本週學習 → 造句: write a sentence with one of the week's words; it corrects how the word is used, then shows
//    the whole sentence corrected.

enum Gemini {
    static let keyKey = "geminiKey"
    static let onKey = "geminiOn"
    static let modelKey = "geminiModel"
    static let defaultModel = "gemini-3.8-flash"
    /// the Flash models to choose from (Google's model list, November 2026): code, name. 2.5: only for keys that
    /// used it before
    static let models: [(String, String)] = [
        ("gemini-3.8-flash", "Gemini 3.8 Flash"),
        ("gemini-3.6-flash", "Gemini 3.6 Flash"),
        ("gemini-3.5-flash-lite", "Gemini 3.5 Flash-Lite"),
        ("gemini-3.1-flash-lite", "Gemini 3.1 Flash-Lite"),
        ("gemini-3-flash-preview", "Gemini 3 Flash (preview)"),
        ("gemini-2.5-flash", "Gemini 2.5 Flash"),
        ("gemini-2.5-flash-lite", "Gemini 2.5 Flash-Lite"),
    ]
    static var key: String { (UserDefaults.standard.string(forKey: keyKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    static var model: String {
        let m = (UserDefaults.standard.string(forKey: modelKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? defaultModel : m
    }
    /// turned on, with a key
    static var on: Bool { UserDefaults.standard.bool(forKey: onKey) && !key.isEmpty }

    enum Failure: Error { case noKey, http(Int, String), empty }

    /// one question; the answer is JSON (an object)
    static func ask(_ prompt: String) async throws -> [String: Any] {
        guard !key.isEmpty else { throw Failure.noKey }
        let name = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? defaultModel
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/" + name + ":generateContent") else { throw Failure.empty }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 40
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0.2],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            let msg = (o?["error"] as? [String: Any])?["message"] as? String ?? ""
            throw Failure.http(code, msg)
        }
        guard let o = try JSONSerialization.jsonObject(with: d) as? [String: Any],
              let c = (o["candidates"] as? [[String: Any]])?.first,
              let parts = (c["content"] as? [String: Any])?["parts"] as? [[String: Any]] else { throw Failure.empty }
        var text = parts.compactMap { $0["text"] as? String }.joined()
        // (sometimes inside a ```json block)
        text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let j = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw Failure.empty }
        return j
    }

    static func message(_ e: Error) -> String {
        guard let f = e as? Failure else { return tr("連不到 Gemini：") + e.localizedDescription }
        switch f {
        case .noKey: return tr("還沒有 Gemini 的 API 金鑰：設定 → 詞典 → Gemini。")
        case .http(let c, let m):
            if c == 400 || c == 401 || c == 403 { return tr("Gemini 不接受這個 API 金鑰（\(c)）。") + (m.isEmpty ? "" : "\n" + m) }
            if c == 429 { return tr("Gemini 現在太忙，或是今天用完了免費的次數（429）。") }
            return tr("Gemini 沒有回答（\(c)）。") + (m.isEmpty ? "" : "\n" + m)
        case .empty: return tr("Gemini 的回答讀不懂。")
        }
    }

    /// what the dictionary is of, and what words to give
    private static func target(_ lang: Int) -> (dict: String, words: String) {
        let script = Simp.on ? "Simplified" : "Traditional"
        switch lang {
        case 4: return ("Japanese dictionary", "Japanese words (dictionary forms, written as a Japanese dictionary would list them)")
        case 5: return ("Swedish dictionary", "Swedish words (base forms, as a Swedish dictionary would list them: no article, no \"att\"; when the search is a meaning in Chinese, English or another language, the Swedish words for it)")
        case 6: return ("English dictionary", "English words (base forms, as an English dictionary would list them: no article, no \"to\"; when the search is a meaning in Chinese, Swedish or another language, the English words for it)")
        case 0: return ("Taiwanese Hokkien dictionary that can also be searched with Mandarin words", "Chinese words (Mandarin as used in Taiwan, \(script) characters)")
        case 2: return ("Cantonese dictionary that can also be searched with Mandarin words", "Chinese words (\(script) characters; Cantonese words or Mandarin ones)")
        case 3: return ("Taiwan Hakka dictionary that can also be searched with Mandarin words", "Chinese words (Mandarin as used in Taiwan, \(script) characters)")
        default: return ("Mandarin Chinese dictionary", "Chinese words (\(script) characters)")
        }
    }

    struct Suggestion { var words: [String] = []; var note = ""; var term: Term? }

    /// 瑞典語, 英語: a word as a dictionary lists it, without the article or infinitive marker Gemini sometimes puts
    /// before it ("att springa" → springa, "to run" → run, "en bil" → bil)
    static func latinHeadword(_ w: String) -> String {
        var s = w.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;\"'")))
        for pre in ["att ", "en ", "ett ", "to ", "a ", "an ", "the "] where s.count > pre.count + 1 && s.lowercased().hasPrefix(pre) {
            s = String(s.dropFirst(pre.count)); break
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
    /// 華語: the search itself, a term Gemini knows (for 自訂)
    struct Term { let h: String; let pinyin: String; let meaning: String }

    static func suggest(_ q: String, lang: Int) async throws -> Suggestion {
        let t = target(lang)
        let han = q.unicodeScalars.contains(where: Zhuyin.isHan)
        var p = """
        A learner searched a \(t.dict) for "\(q)" and it found nothing. Work out what they most likely meant: it may be \
        misspelt, typed in a romanisation (pinyin, zhuyin, Jyutping, Tâi-lô, Hakka pinyin, rōmaji…), written in English \
        or another language, a description, slang, a name or a new expression.
        Reply with JSON only: {"words": [...], "note": "..."}
        "words": up to 8 \(t.words), the most likely first; each one a single dictionary word or set phrase, nothing else \
        (no readings, no explanations).
        "note": at most one short sentence in \(Simp.on ? "Simplified" : "Traditional") Chinese on what the search most likely was.
        """
        if han && (lang == 1 || lang == 0) {
            p += """

            If "\(q)" itself is a real Chinese word, expression, name or slang term, also add "term": {"pinyin": its \
            Mandarin reading in pinyin with tone numbers, one syllable per character separated by spaces (e.g. "chi1 fan4"), \
            "meaning": a short explanation in \(Simp.on ? "Simplified" : "Traditional") Chinese}. Otherwise "term": null.
            """
        }
        let j = try await ask(p)
        var s = Suggestion()
        s.words = ((j["words"] as? [Any]) ?? []).compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { lang == 5 || lang == 6 ? latinHeadword($0) : $0 }.filter { !$0.isEmpty && $0 != q }
        var seenWords = Set<String>()
        s.words = s.words.filter { seenWords.insert($0).inserted }
        s.note = j["note"] as? String ?? ""
        if let tm = j["term"] as? [String: Any], let py = tm["pinyin"] as? String, !py.isEmpty {
            s.term = Term(h: q, pinyin: py, meaning: tm["meaning"] as? String ?? "")
        }
        return s
    }

    struct Correction { let usage: String; let corrected: String; let good: Bool }
    /// 造句: how the word is used in the sentence, then the whole sentence corrected
    static func correct(word: String, reading: String, meaning: String, sentence: String, lang: Int) async throws -> Correction {
        let language = ["Taiwanese Hokkien (written in Han characters as the Taiwan Ministry of Education does)", "Mandarin Chinese",
                        "Cantonese", "Taiwan Hakka", "Japanese", "Swedish", "English"][min(max(lang, 0), 6)]
        let p = """
        A learner of \(language) wrote a sentence to practise the word "\(word)"\(reading.isEmpty ? "" : " (\(reading))")\
        \(meaning.isEmpty ? "" : ", meaning: \(meaning)").
        Sentence: "\(sentence)"
        Reply with JSON only: {"good": true or false, "usage": "...", "corrected": "..."}
        "good": whether "\(word)" is used correctly and naturally.
        "usage": 1–3 short sentences in \(Simp.on ? "Simplified" : "Traditional") Chinese, only about how "\(word)" is used \
        here: is it right, and if not, how it should be used (with a better way to say that part). Don't comment on \
        the rest of the sentence here.
        "corrected": the whole sentence corrected (grammar, word choice, punctuation) in \(language), as natural as \
        possible while keeping what the learner meant; the same sentence if it's already right.
        """
        let j = try await ask(p)
        guard let u = j["usage"] as? String else { throw Failure.empty }
        return Correction(usage: u, corrected: j["corrected"] as? String ?? sentence, good: j["good"] as? Bool ?? false)
    }
}

// MARK: 設定

struct GeminiSettingsSection: View {
    @AppStorage(Gemini.onKey) private var on = false
    @AppStorage(Gemini.keyKey) private var key = ""
    @AppStorage(Gemini.modelKey) private var model = ""
    @State private var testing = false
    @State private var result: String?

    var body: some View {
        Section {
            Toggle(tr("用 Gemini 幫忙"), isOn: $on)
            SecureField(tr("API 金鑰"), text: $key)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            let current = model.isEmpty ? Gemini.defaultModel : model
            Picker(tr("模型"), selection: Binding(get: { current }, set: { model = $0 })) {
                ForEach(Gemini.models, id: \.0) { Text($0.1).tag($0.0) }
                // (one typed in an older version, not on the list)
                if !Gemini.models.contains(where: { $0.0 == current }) { Text(current).tag(current) }
            }
            Button(testing ? tr("試試看中…") : tr("試試看")) { test() }.disabled(testing || key.isEmpty)
            if let result { Text(result).ffFont(.footnote).foregroundStyle(T.muted) }
        } header: {
            Text("Gemini")
        } footer: {
            Text(tr("用你自己的 Google Gemini API 金鑰（在 Google AI Studio 免費申請）。打開以後：查詞找不到的時候，會問 Gemini 你可能要找的詞，再用詞典找出來；華語可以把它認得的詞加到「自訂」；本週學習多一個「造句」練習，Gemini 改你的句子。只有用到的時候才會把你查的字或寫的句子送給 Google。金鑰只存在這台裝置上。"))
        }
    }

    private func test() {
        testing = true; result = nil
        Task {
            do {
                let s = try await Gemini.suggest("chifan", lang: 1)
                result = tr("可以用了。（chifan → \(s.words.prefix(3).joined(separator: "、"))）")
            } catch { result = Gemini.message(error) }
            testing = false
        }
    }
}

// MARK: 查詞找不到 → Gemini

/// put in a search's List when it found nothing: the words Gemini thinks were meant. `row` shows a word the
/// dictionary has (nil: it hasn't, shown as a button that searches it); `addTerm`: 華語's add-to-自訂
struct GeminiSuggestSection: View {
    let query: String
    let lang: Int
    var search: (String) -> Void
    var row: (String) -> AnyView?
    var addTerm: ((Gemini.Term) -> Void)? = nil
    /// a word Gemini gave that the dictionary doesn't have: saved as your own word (自訂), its meaning what was searched
    var addOwn: ((String) -> Void)? = nil
    @AppStorage(Gemini.onKey) private var on = false
    @AppStorage(Gemini.keyKey) private var key = ""
    @State private var got: Gemini.Suggestion?
    @State private var gotFor = ""
    @State private var failed: String?
    @State private var asking = false

    var body: some View {
        if on && !key.isEmpty {
            Section {
                if asking && gotFor != query {
                    HStack(spacing: 8) { ProgressView(); Text(tr("問 Gemini 中…")).foregroundStyle(T.muted) }
                } else if let failed {
                    Text(failed).ffFont(.footnote).foregroundStyle(T.rustInk)
                } else if let g = got, gotFor == query {
                    if !g.note.isEmpty { Text(g.note).ffFont(.footnote).foregroundStyle(T.muted) }
                    ForEach(g.words, id: \.self) { w in
                        if let r = row(w) { r } else {
                            HStack {
                                Button { search(w) } label: {
                                    HStack {
                                        Text(w).scaledFont(19, weight: .semibold).foregroundStyle(T.glyph)
                                        Spacer()
                                        Image(systemName: "magnifyingglass").foregroundStyle(T.btnInk)
                                    }
                                }
                                .buttonStyle(.plain)
                                // (not in the dictionary: kept as your own word, meaning what you searched)
                                if let addOwn {
                                    Button { addOwn(w) } label: {
                                        Label(tr("存成自訂詞"), systemImage: "plus.circle").labelStyle(.iconOnly).foregroundStyle(T.ownInk)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(tr("存成自訂詞"))
                                }
                            }
                        }
                    }
                    if g.words.isEmpty { Text(tr("Gemini 也不知道。")).foregroundStyle(T.muted) }
                    if let t = g.term, let addTerm {
                        Button { addTerm(t) } label: {
                            Label(tr("把「\(t.h)」加到自訂（\(t.pinyin)）"), systemImage: "plus.circle").foregroundStyle(T.ownInk)
                        }
                    }
                }
            } header: {
                Text(tr("Gemini 猜你要找的詞")).textCase(nil)
            } footer: {
                Text(addOwn == nil ? tr("Gemini 猜的，不是詞典的內容：點一個詞，再用詞典查。")
                     : tr("Gemini 猜的，不是詞典的內容：點一個詞，再用詞典查。詞典沒有的詞，按旁邊的＋存成自訂詞（意思先填你查的「\(query)」）。"))
            }
            .listRowBackground(T.fn.opacity(0.7))
            .task(id: query) { await run() }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, gotFor != query else { return }
        failed = nil
        asking = true
        // (only once typing has stopped for a moment: a new query cancels this)
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard !Task.isCancelled else { return }
        do {
            let s = try await Gemini.suggest(q, lang: lang)
            guard !Task.isCancelled else { return }
            got = s; gotFor = query
        } catch {
            if !Task.isCancelled { failed = Gemini.message(error) }
        }
        asking = false
    }
}

/// (for a sheet)
struct GeminiTermItem: Identifiable { let id = UUID(); let term: Gemini.Term }
/// (a word Gemini gave, to save as your own: the word and what was searched, as its meaning)
struct GeminiOwnItem: Identifiable { let id = UUID(); let word: String; let meaning: String }

// MARK: 本週學習 → 造句

struct UsagePracticeView: View {
    let words: [Card]
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @State private var i = 0
    @State private var sentence = ""
    @State private var result: Gemini.Correction?
    @State private var failed: String?
    @State private var asking = false
    @FocusState private var focused: Bool

    private var card: Card? { words.isEmpty ? nil : words[i % words.count] }

    var body: some View {
        NavigationStack {
            Form {
                if !Gemini.on {
                    Section {
                        Text(tr("這個練習要用 Gemini：在 設定 → 詞典 → Gemini 打開，填你自己的 API 金鑰。")).foregroundStyle(T.muted)
                    }
                }
                if let c = card {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(c.h).scaledFont(34, weight: .bold).foregroundStyle(T.glyph)
                            Text(store.cardRom(c, rom, place)).latFont(18).foregroundStyle(T.greenInk)
                            ForEach(Array(c.d.prefix(2).enumerated()), id: \.offset) { n, d in
                                Text((c.d.count > 1 ? "\(n + 1). " : "") + d.t).ffFont(.subheadline).foregroundStyle(T.muted)
                            }
                            if let x = c.d.first?.x.first {
                                Text(tr("例：") + x.h).ffFont(.footnote).foregroundStyle(T.muted)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: { Text(tr("用這個詞造一個句子（\(i % max(words.count, 1) + 1)／\(words.count)）")) }
                    Section {
                        TextField(tr("你的句子"), text: $sentence, axis: .vertical)
                            .focused($focused)
                            .lineLimit(2...5)
                        Button(asking ? tr("Gemini 改句子中…") : tr("請 Gemini 改")) { check(c) }
                            .disabled(asking || sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !Gemini.on)
                    }
                    if let failed { Section { Text(failed).foregroundStyle(T.rustInk) } }
                    if let r = result {
                        Section(tr("這個詞的用法")) {
                            Label(r.good ? tr("用對了") : tr("用法要改"), systemImage: r.good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(r.good ? T.greenInk : T.rustInk)
                            Text(r.usage).textSelection(.enabled)
                        }
                        Section(tr("整句改好")) {
                            Text(r.corrected).scaledFont(20).foregroundStyle(T.glyph).textSelection(.enabled)
                        }
                        Section {
                            Button(tr("下一個詞")) { next() }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(tr("造句"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(tr("換一個詞")) { next() }.disabled(words.count < 2) }
            }
        }
    }

    private func next() { i += 1; sentence = ""; result = nil; failed = nil; focused = true }

    private func check(_ c: Card) {
        asking = true; failed = nil; result = nil
        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = String(store.cardRom(c, rom, place).characters)
        let meaning = c.d.prefix(2).map(\.t).joined(separator: "；")
        let lang = Lang.kind(c.k)
        Task {
            do { result = try await Gemini.correct(word: c.h, reading: reading, meaning: meaning, sentence: s, lang: lang) }
            catch { failed = Gemini.message(error) }
            asking = false
        }
    }
}
