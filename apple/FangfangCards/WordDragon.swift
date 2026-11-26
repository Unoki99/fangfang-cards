import SwiftUI
import PencilKit
import Vision

// MARK: - 詞龍 (詞語接龍)
//
// The app gives a word; you type one that starts with its last character (瑞典語: its last letter); then the app
// answers with one starting with your word's last, and so on. Every word must be in the dictionary of the language
// shown, and no word twice. The app runs out: you win the round. 手寫: write the word on the pad instead (read by
// iOS's own text recognition, Vision); tap one of what it read to put it in.

struct WordDragonView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    private struct Link: Identifiable { let id = UUID(); let word: String; let mine: Bool }
    @State private var chain: [Link] = []
    @State private var typed = ""
    @State private var said: String?          // why a word wasn't taken
    @State private var won = false
    @State private var best = UserDefaults.standard.integer(forKey: "dragonBest")
    @FocusState private var focused: Bool
    /// the words the app may answer with, by their first unit (the common ones first)
    @State private var byFirst: [String: [String]] = [:]
    /// 手寫: the pad, what's drawn, and what Vision read in it
    @AppStorage("dragonHand") private var hand = false
    @State private var drawing = PKDrawing()
    @State private var clearN = 0
    @State private var read: [String] = []

    private var sv: Bool { store.isSv }
    private var used: Set<String> { Set(chain.map { norm($0.word) }) }
    private var mineCount: Int { chain.filter(\.mine).count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(chain) { l in row(l).id(l.id) }
                            if won {
                                Text(tr("App 接不下去了，你贏了！")).ffFont(.headline).foregroundStyle(T.blueInk).padding(.top, 6)
                            }
                        }
                        .padding()
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: chain.count) { if let l = chain.last { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } } }
                }
                VStack(spacing: 8) {
                    if let said { Text(said).ffFont(.footnote).foregroundStyle(T.rustInk).frame(maxWidth: .infinity, alignment: .leading) }
                    if hand { pad }
                    HStack(spacing: 10) {
                        if let need = need { Text(need).scaledFont(24, weight: .bold).foregroundStyle(T.btnInk).frame(minWidth: 34) }
                        TextField(sv ? tr("打一個瑞典文的詞") : tr("打一個詞"), text: $typed)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.send)
                            .onSubmit { submit() }
                            .scaledFont(20)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.75)))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
                            .disabled(won)
                        Button { submit() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                            .buttonStyle(.plain).foregroundStyle(T.btnInk)
                            .disabled(won || typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        Text(tr("接了 \(mineCount) 個・最多 \(best) 個")).ffFont(.caption).foregroundStyle(T.muted)
                        Spacer()
                        Button(tr("換一個詞")) { start() }.ffFont(.caption)
                    }
                }
                .padding()
                .background(T.fn.opacity(0.35))
            }
            .appBackground()
            .navigationTitle(tr("詞龍"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { hand.toggle(); focused = !hand } label: { Image(systemName: hand ? "keyboard" : "pencil.and.scribble") }
                        .accessibilityLabel(hand ? tr("打字") : tr("手寫"))
                }
                if !sv { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
            }
        }
        .onAppear { if chain.isEmpty { build(); start() } }
        // (read a moment after the last stroke)
        .task(id: drawing.strokes.count) {
            guard hand, !drawing.strokes.isEmpty else { read = []; return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            read = await InkReader.read(drawing, langs: sv ? ["sv-SE", "en-US"] : (Simp.on ? ["zh-Hans", "zh-Hant"] : ["zh-Hant", "zh-Hans"]))
        }
    }

    /// 手寫: the pad, what was read (tap one to put it in), 清掉
    private var pad: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.97))
                InkPad(drawing: $drawing, clear: clearN)
                Button { clearN += 1; read = [] } label: { Image(systemName: "eraser").padding(10) }
                    .buttonStyle(.plain).foregroundStyle(Color(white: 0.35))
            }
            .frame(height: 170)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.fnEdge, lineWidth: 1))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if read.isEmpty {
                        Text(drawing.strokes.isEmpty ? tr("在上面寫一個詞") : tr("看不出來，再寫清楚一點")).ffFont(.caption).foregroundStyle(T.muted)
                    }
                    ForEach(read, id: \.self) { w in
                        Button { typed += w; clearN += 1; read = [] } label: {
                            Text(w).scaledFont(22, weight: .semibold).foregroundStyle(T.glyph)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(Capsule().fill(T.fn))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// the character (or letter) the next word must start with
    private var need: String? { chain.last.flatMap { last($0.word) } }

    private func row(_ l: Link) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: l.mine ? "person.fill" : "sparkles").ffFont(.caption).foregroundStyle(l.mine ? T.blueInk : T.oliveInk)
            Text(l.word).scaledFont(26, weight: .semibold).foregroundStyle(T.glyph)
            if let r = reading(l.word) { Text(r).latFont(16).foregroundStyle(T.greenInk) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: l.mine ? .trailing : .leading)
    }

    // MARK: words

    private func norm(_ w: String) -> String { sv ? w.lowercased() : w }
    private func first(_ w: String) -> String? { (sv ? w.lowercased() : w).first.map(String.init) }
    private func last(_ w: String) -> String? {
        if sv { return w.lowercased().last(where: { $0.isLetter }).map(String.init) }
        return w.last(where: { $0.unicodeScalars.first.map(Zhuyin.isHan) ?? false }).map(String.init) ?? w.last.map(String.init)
    }

    /// a word of the language shown (in its dictionary)
    private func isWord(_ w: String) -> Bool {
        if !store.isZh { return store.dict?.hanMap[w] != nil }
        guard let z = store.zh else { return false }
        if z.isSv { return !z.svIndices(w).isEmpty }
        return z.byHan[w] != nil
    }

    /// the word's reading, when it's one of the cards
    private func reading(_ w: String) -> String? {
        if sv { return nil }
        guard let c = store.cards.first(where: { $0.h == w }) else { return nil }
        return String(store.cardRom(c, rom, place).characters)
    }

    /// the app's words: the cards (most common first), two units or more
    private func build() {
        var m: [String: [String]] = [:]
        for c in store.cards where Lang.charOf(c.k) == nil {
            let w = c.h
            guard (sv ? w.count >= 3 : w.count >= 2), !w.contains(" "), let f = first(w) else { continue }
            m[f, default: []].append(w)
        }
        byFirst = m
    }

    private func start() {
        typed = ""; said = nil; won = false
        // (a common word that can be followed)
        let pool = byFirst.values.flatMap { $0.prefix(30) }.filter { w in last(w).map { byFirst[$0] != nil } ?? false }
        if let w = pool.randomElement() { chain = [Link(word: w, mine: false)] } else { chain = [] }
        focused = !hand
    }

    private func submit() {
        let w = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !won else { return }
        if let n = need, first(w) != n { said = tr("要用「\(n)」開頭。"); return }
        if used.contains(norm(w)) { said = tr("這個詞用過了。"); return }
        if !isWord(w) { said = tr("詞典裡沒有「\(w)」。"); return }
        said = nil
        typed = ""
        chain.append(Link(word: w, mine: true))
        if mineCount > best { best = mineCount; UserDefaults.standard.set(best, forKey: "dragonBest") }
        // the app's turn
        let u = used
        if let l = last(w), let reply = (byFirst[l] ?? []).first(where: { !u.contains(norm($0)) }) {
            chain.append(Link(word: reply, mine: false))
        } else {
            won = true
        }
        focused = !hand
    }
}

// MARK: - 手寫: a plain pad, and reading it with Vision

struct InkPad: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let clear: Int
    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.drawingPolicy = .anyInput
        v.backgroundColor = .clear
        v.isOpaque = false
        // (light: the ink stays black on the light pad in dark mode too)
        v.overrideUserInterfaceStyle = .light
        v.tool = PKInkingTool(.pen, color: .black, width: 7)
        v.delegate = context.coordinator
        return v
    }
    func updateUIView(_ v: PKCanvasView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if c.cleared != clear { c.cleared = clear; v.drawing = PKDrawing() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: InkPad
        var cleared: Int
        init(_ p: InkPad) { parent = p; cleared = p.clear }
        func canvasViewDrawingDidChange(_ v: PKCanvasView) {
            let d = v.drawing
            DispatchQueue.main.async { self.parent.drawing = d }
        }
    }
}

enum InkReader {
    /// what the drawing says, the likeliest first (a few guesses)
    @MainActor static func read(_ d: PKDrawing, langs: [String]) async -> [String] {
        guard !d.strokes.isEmpty else { return [] }
        let box = d.bounds.insetBy(dx: -24, dy: -24)
        // (black ink on white: Vision reads an opaque picture)
        let ink = d.image(from: box, scale: 2)
        let img = UIGraphicsImageRenderer(size: box.size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 2; f.opaque = true; return f }()).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: box.size))
            ink.draw(in: CGRect(origin: .zero, size: box.size))
        }
        guard let cg = img.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            if let ok = try? req.supportedRecognitionLanguages() {
                let use = langs.filter { ok.contains($0) }
                if !use.isEmpty { req.recognitionLanguages = use }
            }
            try? VNImageRequestHandler(cgImage: cg).perform([req])
            let obs = (req.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            guard !obs.isEmpty else { return [] }
            var out: [String] = []
            if obs.count == 1 {
                out = obs[0].topCandidates(5).map(\.string)
            } else {
                out = [obs.compactMap { $0.topCandidates(1).first?.string }.joined()]
            }
            var seen = Set<String>()
            return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "") }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
        }.value
    }
}
