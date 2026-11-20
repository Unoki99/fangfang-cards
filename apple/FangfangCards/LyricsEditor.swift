import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

// 自己的歌詞: type or paste a song's lyrics, then time them while the song plays: one tap as each line starts.
// Kept on this device as LRC (the same timed format LRCLIB uses) and used whenever that song plays, before LRCLIB's.
// Also for fixing the timing of LRCLIB's lyrics: they're the starting point when there are no lyrics of your own.

struct OwnLyric: Codable {
    var trackId: Int
    var trackName: String
    var artistName: String
    var duration: Double?
    /// the lyrics with their times, LRC: "[01:23.45]words"
    var lrc: String
    var date = Date()

    /// as lyrics for the 歌詞 window (an id of its own, apart from LRCLIB's)
    var hit: LyricHit {
        LyricHit(id: -trackId, trackName: trackName, artistName: artistName, duration: duration, plain: nil, synced: lrc)
    }
}

/// the songs' lyrics of your own, in a file on this device
@MainActor
final class OwnLyrics: ObservableObject {
    static let shared = OwnLyrics()
    @Published private(set) var items: [Int: OwnLyric] = [:]

    private var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("own-lyrics.json")
    }

    private init() {
        if let d = try? Data(contentsOf: file), let all = try? JSONDecoder().decode([OwnLyric].self, from: d) {
            for x in all { items[x.trackId] = x }
        }
    }

    func get(_ trackId: Int) -> OwnLyric? { items[trackId] }

    func set(_ x: OwnLyric) {
        items[x.trackId] = x
        deleted.remove(x.trackId)
        write()
    }

    func remove(_ trackId: Int) {
        items[trackId] = nil
        deleted.insert(trackId)
        write()
    }

    private func write() {
        if let d = try? JSONEncoder().encode(Array(items.values)) { try? d.write(to: file, options: .atomic) }
    }

    // MARK: 歌詞 folder (in the backup folder: every device's lyrics of your own, one .lrc file a song)

    static let folderName = "歌詞"
    /// (lyrics deleted here since the last sync: their file goes, and a mark so the other devices delete theirs)
    private var deleted: Set<Int> {
        get { Set(UserDefaults.standard.array(forKey: "ownLyricsDeleted") as? [Int] ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "ownLyricsDeleted") }
    }

    /// "繁華夢 - 黃齡 [1234567].lrc" (the number: the song in Apple's catalogue)
    static func fileName(_ x: OwnLyric) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r")
        let clean = { (s: String) in s.components(separatedBy: bad).joined(separator: " ").trimmingCharacters(in: .whitespaces) }
        return clean(x.trackName) + " - " + clean(x.artistName) + " [\(x.trackId)].lrc"
    }

    private static func trackId(of name: String) -> Int? {
        guard name.hasSuffix(".lrc"), let open = name.lastIndex(of: "["), let close = name.lastIndex(of: "]"), open < close else { return nil }
        return Int(name[name.index(after: open)..<close])
    }

    /// an LRC file as lyrics of your own ([ti:], [ar:] and [length:] give the song's name, singer and length)
    static func fromLRC(_ text: String, trackId: Int, date: Date) -> OwnLyric {
        func tag(_ k: String) -> String? {
            guard let r = text.range(of: "[" + k + ":") else { return nil }
            let rest = text[r.upperBound...]
            guard let end = rest.firstIndex(of: "]") else { return nil }
            return String(rest[..<end]).trimmingCharacters(in: .whitespaces)
        }
        var length: Double?
        if let l = tag("length") {
            let p = l.split(separator: ":").compactMap { Double($0) }
            if p.count == 2 { length = p[0] * 60 + p[1] }
        }
        return OwnLyric(trackId: trackId, trackName: tag("ti") ?? "", artistName: tag("ar") ?? "", duration: length, lrc: text, date: date)
    }

    /// (called by the backup's sync, with the folder open) lyrics newer in the folder come in, ours go out, deleted ones
    /// go everywhere; returns how many came in
    func sync(in folder: URL) -> Int {
        let fm = FileManager.default
        let dir = folder.appendingPathComponent(Self.folderName, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        var files: [Int: (url: URL, date: Date)] = [:]
        var marks: [Int: Date] = [:]
        for n in names {
            let u = dir.appendingPathComponent(n)
            if n.hasPrefix(".") && n.hasSuffix(".icloud") {
                // (not downloaded yet: fetched for next time)
                try? fm.startDownloadingUbiquitousItem(at: dir.appendingPathComponent(String(n.dropFirst().dropLast(".icloud".count))))
                continue
            }
            let date = ((try? fm.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date) ?? .distantPast
            if n.hasSuffix(".deleted"), let id = Int(n.dropLast(".deleted".count)) { marks[id] = date; continue }
            if let id = Self.trackId(of: n) { files[id] = (u, date) }
        }
        var came = 0, changed = false
        // deleted here: the file goes, a mark stays for the others
        for id in deleted {
            if let f = files[id] { try? fm.removeItem(at: f.url); files[id] = nil }
            try? Data().write(to: dir.appendingPathComponent("\(id).deleted"))
        }
        deleted = []
        // deleted on another device after we last changed it: ours goes too
        for (id, when) in marks {
            if let x = items[id], x.date < when { items[id] = nil; changed = true; came += 1 }
        }
        // in the folder, newer than ours (or not here): in
        for (id, f) in files where marks[id].map({ $0 < f.date }) ?? true {
            guard let d = Self.read(f.url), let text = String(data: d, encoding: .utf8) else { continue }
            if let x = items[id] {
                if x.lrc == text || x.date >= f.date.addingTimeInterval(-1) { continue }
            }
            var x = Self.fromLRC(text, trackId: id, date: f.date)
            if let old = items[id] {
                if x.trackName.isEmpty { x.trackName = old.trackName }
                if x.artistName.isEmpty { x.artistName = old.artistName }
            }
            items[id] = x
            changed = true
            came += 1
        }
        // ours, not in the folder or newer: out (the file then dated as ours, so it isn't taken back in)
        for (id, x) in items {
            if let f = files[id], let d = Self.read(f.url), String(data: d, encoding: .utf8) == x.lrc { continue }
            if let f = files[id], f.date > x.date.addingTimeInterval(1) { continue }
            if let f = files[id], f.url.lastPathComponent != Self.fileName(x) { try? fm.removeItem(at: f.url) }
            let u = dir.appendingPathComponent(Self.fileName(x))
            if Self.write(Data(x.lrc.utf8), to: u) {
                try? fm.setAttributes([.modificationDate: x.date], ofItemAtPath: u.path)
            }
            try? fm.removeItem(at: dir.appendingPathComponent("\(id).deleted"))
        }
        if changed {
            write()
            // (the song playing has new lyrics of its own: shown)
            if let s = SongPlayer.shared.song, items[s.id]?.lrc != LyricsBridge.shared.song.flatMap({ $0.id == -s.id ? $0.syncedLyrics : nil }) {
                SongPlayer.shared.reloadLyrics()
            }
        }
        return came
    }

    private static func read(_ url: URL) -> Data? {
        var out: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in out = try? Data(contentsOf: u) }
        return out
    }

    private static func write(_ data: Data, to url: URL) -> Bool {
        var ok = false
        var err: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            ok = (try? data.write(to: u, options: .atomic)) != nil
        }
        return ok
    }
}

/// one line while timing (text "" is a break between lines, 間奏)
struct TimedLine: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var t: Double?
    /// when each of the line's pieces (LRC.pieces) starts, when they were moved by hand; nil: spread evenly
    var words: [Double]? = nil
}

enum LRC {
    /// 1:23.45 → "[01:23.45]"
    static func stamp(_ t: Double) -> String {
        let cs = Int((max(0, t) * 100).rounded())
        return String(format: "[%02d:%02d.%02d]", cs / 6000, (cs / 100) % 60, cs % 100)
    }

    /// 1:23.45 → "<01:23.45>" (a word's time inside a line)
    static func wordStamp(_ t: Double) -> String { "<" + String(stamp(t).dropFirst().dropLast()) + ">" }

    /// the pieces a line's word times go by: every 漢字 (or kana, hangul) its own, other words by the spaces;
    /// punctuation and spaces go with the piece before. Joined they're the line again; each has a letter.
    static func pieces(_ text: String) -> [String] {
        var out: [String] = []
        var cur = "", letters = 0, curCJK = false, gap = false
        for ch in text {
            guard ch.isLetter || ch.isNumber else {
                cur.append(ch)
                if ch.isWhitespace { gap = true }
                continue
            }
            let cjk = ch.unicodeScalars.first.map { isCJK($0.value) } ?? false
            if letters > 0 && (cjk || curCJK || gap) {
                out.append(cur); cur = ""; letters = 0
            }
            cur.append(ch); letters += 1; curCJK = cjk; gap = false
        }
        if !cur.isEmpty {
            if letters == 0, !out.isEmpty { out[out.count - 1] += cur } else { out.append(cur) }
        }
        return out
    }

    private static func isCJK(_ v: UInt32) -> Bool {
        (0x3040...0x30FF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v)
            || (0xF900...0xFAFF).contains(v) || (0x20000...0x3134F).contains(v) || (0xAC00...0xD7AF).contains(v)
    }

    /// letters before each piece
    static func pieceStarts(_ ps: [String]) -> [Int] {
        var acc = 0
        return ps.map { p in
            defer { acc += p.filter { $0.isLetter || $0.isNumber }.count }
            return acc
        }
    }

    /// the line's words with their word times in them (only when they were moved by hand)
    static func withWords(_ l: TimedLine) -> String {
        guard l.t != nil, let w = l.words else { return l.text }
        let ps = pieces(l.text)
        guard ps.count >= 2, ps.count == w.count else { return l.text }
        return zip(ps, w).map { wordStamp($1) + $0 }.joined()
    }

    /// "1:23.4" for showing
    static func shown(_ t: Double) -> String {
        let ds = Int((max(0, t) * 10).rounded())
        return String(format: "%d:%02d.%d", ds / 600, (ds / 10) % 60, ds % 10)
    }

    /// the lines written out as LRC. Lines without a time get one between their neighbours'; breaks without one are left out.
    static func make(_ lines: [TimedLine], title: String, artist: String, length: Double?) -> String {
        var ls = lines.filter { !($0.text.isEmpty && $0.t == nil) }
        var guessed: [Double] = []
        // (untimed lines: spread evenly between the timed ones around them)
        var i = 0
        while i < ls.count {
            if ls[i].t != nil { i += 1; continue }
            var j = i
            while j < ls.count && ls[j].t == nil { j += 1 }
            let before = i > 0 ? ls[i - 1].t ?? 0 : 0
            let after = j < ls.count ? ls[j].t ?? (before + Double(j - i + 1) * 3) : before + Double(j - i + 1) * 3
            let step = (after - before) / Double(j - i + 1)
            for k in i..<j {
                ls[k].t = ((before + step * Double(k - i + 1)) * 100).rounded() / 100
                guessed.append(ls[k].t ?? 0)
            }
            i = j
        }
        var out = ["[ti:\(title)]", "[ar:\(artist)]"]
        if let l = length, l > 0 { out.append(String(format: "[length:%02d:%02d]", Int(l) / 60, Int(l) % 60)) }
        out.append("[by:方方詞卡]")
        // (the lines given a time only so the file has one: not timed yet, as the editor shows when it's opened again)
        if !guessed.isEmpty { out.append("[ff-untimed:" + guessed.map { String(format: "%.2f", $0) }.joined(separator: ",") + "]") }
        for l in ls { out.append(stamp(l.t ?? 0) + withWords(l)) }
        return out.joined(separator: "\n")
    }

    /// LRC (or LRCLIB's lyrics) → the lines with their times, breaks included
    static func lines(from h: LyricHit) -> [TimedLine] {
        if let rows = h.timedRows {
            var out: [TimedLine] = []
            for r in rows {
                // (word times back onto the line's pieces, when every piece has one)
                var words: [Double]?
                if r.times.count == 1, r.marks.count >= 2 {
                    let ps = pieces(r.text)
                    let ws = pieceStarts(ps).map { at in r.marks.first(where: { $0.at == at })?.t }
                    if ps.count >= 2, !ws.contains(where: { $0 == nil }) { words = ws.compactMap { $0 } }
                }
                for t in r.times { out.append(TimedLine(text: r.text, t: t, words: words)) }
            }
            out.sort { ($0.t ?? 0) < ($1.t ?? 0) }
            while out.first?.text.isEmpty == true { out.removeFirst() }
            // (lines saved before they were timed: untimed again)
            if let s = h.syncedLyrics, let r = s.range(of: "[ff-untimed:"), let end = s[r.upperBound...].firstIndex(of: "]") {
                let gs = s[r.upperBound..<end].split(separator: ",").compactMap { Double($0) }
                for i in out.indices { if let t = out[i].t, gs.contains(where: { abs($0 - t) < 0.006 }) { out[i].t = nil } }
            }
            return out
        }
        return lines(fromText: h.text ?? "", keeping: [])
    }

    /// typed text → lines (an empty line: a break; several in a row count once); the times kept for lines that
    /// didn't change
    static func lines(fromText text: String, keeping old: [TimedLine]) -> [TimedLine] {
        var out: [TimedLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.isEmpty && (out.isEmpty || out.last?.text.isEmpty == true) { continue }
            out.append(TimedLine(text: s, t: nil))
        }
        // (an empty line at the very end stays: where the last line stops being sung)
        for i in out.indices where i < old.count && old[i].text == out[i].text { out[i].t = old[i].t; out[i].words = old[i].words }
        return out
    }
}

/// what both of 歌詞對時's pages work on: the words, their times, where the next tap goes, the line being sung
@MainActor
final class LyricsEditModel: ObservableObject {
    @Published var text = ""
    @Published var lines: [TimedLine] = [] { didSet { updateSung(SongPlayer.shared.time) } }
    /// the line the next tap times
    @Published var cursor = 0
    /// the line tapped in the list (空行 goes under it while the song is paused)
    @Published var focus: Int?
    /// a line chosen by tapping it: 空行 goes under that one, playing or not (until a tap times a line)
    @Published var picked: Int?
    /// (復原: the lines, the next line and the chosen one as they were before each change in the timing)
    private var history: [(lines: [TimedLine], cursor: Int, focus: Int?, picked: Int?)] = []
    @Published private(set) var canUndo = false

    /// (before a change: kept so 復原 can bring it back; the last 200)
    func remember() {
        history.append((lines, cursor, focus, picked))
        if history.count > 200 { history.removeFirst() }
        canUndo = true
    }

    /// a line's word times set by hand: the same line sung again later (the same words exactly) gets the same timing,
    /// stretched to its own length, as long as that one has no word times of its own yet (it can still be changed
    /// on its own afterwards)
    func shareWords(from i: Int) {
        guard lines.indices.contains(i), let w = lines[i].words, let t0 = lines[i].t else { return }
        let span = max(0.2, endOf(i) - t0)
        for j in lines.indices where j != i && lines[j].text == lines[i].text && lines[j].words == nil {
            guard let s = lines[j].t else { continue }
            let span2 = max(0.2, endOf(j) - s)
            lines[j].words = w.map { ((s + ($0 - t0) / span * span2) * 100).rounded() / 100 }
        }
    }

    /// a line moved earlier or later: its word times with it
    func shiftWords(_ i: Int, by d: Double) {
        guard lines.indices.contains(i), let w = lines[i].words, d != 0 else { return }
        lines[i].words = w.map { max(0, (($0 + d) * 100).rounded() / 100) }
    }

    func undo() {
        guard let h = history.popLast() else { return }
        lines = h.lines; cursor = h.cursor; focus = h.focus; picked = h.picked
        canUndo = !history.isEmpty
    }
    /// the line being sung now, by the times given so far (changes only when the line does: the list isn't
    /// redrawn four times a second)
    @Published private(set) var sung: Int?
    private var sub: AnyCancellable?

    init() {
        sub = SongClock.shared.$time.sink { [weak self] t in
            Task { @MainActor in self?.updateSung(t) }
        }
    }

    /// kept as this song's own lyrics; playing now: the lyrics follow the new times right away
    func save(_ song: SongHit) {
        let lrc = LRC.make(lines, title: song.trackName, artist: song.artistName, length: song.seconds)
        let x = OwnLyric(trackId: song.id, trackName: song.trackName, artistName: song.artistName, duration: song.seconds, lrc: lrc)
        OwnLyrics.shared.set(x)
        if SongPlayer.shared.song?.id == song.id { LyricsBridge.shared.put(x.hit) }
    }

    /// 重複這一句: the line played over and over (nil: off)
    @Published var loopLine: Int? { didSet { loopChanged() } }
    private var loopTimer: Timer?

    /// where line i stops being sung: the next line's time (a 間奏 counts), else a few seconds on
    func endOf(_ i: Int) -> Double {
        let t = lines.indices.contains(i) ? lines[i].t ?? 0 : 0
        if i + 1 < lines.count, let n = lines[(i + 1)...].first(where: { $0.t != nil })?.t, n > t + 0.2 { return n }
        return t + 4
    }

    private func loopChanged() {
        loopTimer?.invalidate(); loopTimer = nil
        // (turned off, or a line without a time: nothing to repeat. Never set loopLine here: it's @Published, so
        // setting it in its own didSet calls didSet again, forever — that was the crash)
        guard let l = loopLine, lines.indices.contains(l), let start = lines[l].t else { return }
        let p = SongPlayer.shared
        p.seek(max(0, start - 0.3))
        if !p.playing { p.togglePause() }
        // (a few times a second: back to the line's start once it's over)
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // (the editor closed: the song plays on normally)
                guard SongPlayer.shared.editing else {
                    self?.loopTimer?.invalidate(); self?.loopTimer = nil
                    if self?.loopLine != nil { self?.loopLine = nil }
                    return
                }
                guard let self, let l = self.loopLine, self.lines.indices.contains(l), let s = self.lines[l].t,
                      let pos = SongPlayer.shared.position else { return }
                if pos >= self.endOf(l) - 0.03 || pos < s - 3 { SongPlayer.shared.seek(max(0, s - 0.3)) }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        loopTimer = t
    }

    func updateSung(_ t: Double) {
        var best: Int?
        for (i, l) in lines.enumerated() {
            if let lt = l.t, lt <= t, best.map({ (lines[$0].t ?? 0) <= lt }) ?? true { best = i }
        }
        if best != sung { sung = best }
    }
}

/// 歌詞對時: a page of its own over the whole app, with two parts picked at the top: 歌詞 (type, paste, or LRCLIB's
/// to fix) and 對時間 (tap along). The song's player above both.
struct LyricsEditor: View {
    let song: SongHit
    @ObservedObject private var own = OwnLyrics.shared
    @StateObject private var m = LyricsEditModel()
    @Environment(\.dismiss) private var dismiss
    /// 0 歌詞, 1 對時間
    @State private var page = 0
    @State private var loaded = false

    @State private var confirmDelete = false
    @State private var importing = false

    var body: some View {
        // (no navigation bar: its buttons were made again every time anything on the page moved, the 時間 bar four
        // times a second, and the ⋯ menu flickered with it)
        VStack(spacing: 10) {
                topBar
                Picker("", selection: $page) {
                    Text(tr("歌詞")).tag(0)
                    Text(tr("對時間")).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                .padding(.horizontal)
                EditorPlayer(song: song).padding(.horizontal)
                if page == 0 {
                    words
                } else {
                    LyricsTimingPage(song: song, m: m) { dismiss() }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .modifier(LRCOpener(open: $importing, song: song, m: m))
        .confirmationDialog(tr("刪除自己的歌詞？之後會用 LRCLIB 的歌詞。"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("刪除"), role: .destructive) {
                own.remove(song.id)
                if SongPlayer.shared.song?.id == song.id { SongPlayer.shared.reloadLyrics() }
                dismiss()
            }
        }
        .onChange(of: page) { _, p in
            // (the words become the lines to time, times kept for lines that didn't change; and back)
            if p == 1 { toLines() } else { m.text = m.lines.map(\.text).joined(separator: "\n") }
        }
        .onAppear(perform: load)
        .onAppear { SongPlayer.shared.editing = true }
        .onDisappear { SongPlayer.shared.editing = false }
    }

    /// 取消 · 自己的歌詞 · ⋯ 儲存
    private var topBar: some View {
        ZStack {
            Text(tr("自己的歌詞")).ffFont(.headline)
            HStack(spacing: 12) {
                Button(tr("取消")) { dismiss() }
                Spacer()
                if page == 1 {
                    // 復原: the last change in the timing taken back
                    Button { m.undo() } label: { Image(systemName: "arrow.uturn.backward").font(.system(size: 18, weight: .semibold)) }
                        .disabled(!m.canUndo)
                        .accessibilityLabel(tr("復原"))
                }
                // (all the file things and the timing settings in one place: ⋯)
                EditorMenu(song: song, m: m, page: page, open: { importing = true }) { confirmDelete = true }
                Button(tr("儲存")) {
                    if page == 0 { toLines() }
                    m.save(song)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(page == 0 ? m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : m.lines.isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    /// ① the words: the whole page to type in
    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("一行一句。空一行是間奏（可以不對時間）。寫好到「對時間」，一邊放歌，一邊在每一句開始唱的時候按一下。"))
                    .ffFont(.footnote).foregroundStyle(T.muted)
                Spacer(minLength: 8)
                Button {
                    if let s = UIPasteboard.general.string { m.text = s }
                } label: { Label(tr("貼上"), systemImage: "doc.on.clipboard") }
                .softButton()
            }
            TextEditor(text: $m.text)
                .scaledFont(17)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
        }
        .padding([.horizontal, .bottom])
    }

    private func toLines() {
        m.lines = LRC.lines(fromText: m.text, keeping: m.lines)
        m.cursor = m.lines.firstIndex(where: { $0.t == nil }) ?? m.lines.count
        m.focus = nil
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let player = SongPlayer.shared
        if let o = own.get(song.id) {
            m.lines = LRC.lines(from: o.hit)
        } else if player.song?.id == song.id, let h = LyricsBridge.shared.song {
            // (LRCLIB's: to fix or time)
            m.lines = LRC.lines(from: h)
        }
        m.text = m.lines.map(\.text).joined(separator: "\n")
        // (already timed: the timing first)
        if !m.lines.isEmpty && m.lines.contains(where: { $0.t != nil }) {
            m.cursor = m.lines.firstIndex(where: { $0.t == nil }) ?? m.lines.count
            page = 1
        }
    }
}

/// ⋯: the lyrics' files (open an .lrc file, share as one), then the timing (how early a tap counts, time everything
/// again), then delete
private struct EditorMenu: View {
    let song: SongHit
    @ObservedObject var m: LyricsEditModel
    let page: Int
    let open: () -> Void
    let delete: () -> Void
    @ObservedObject private var own = OwnLyrics.shared
    @AppStorage("lrcReaction") private var reaction = 0.15
    @State private var share: ShareItem?
    var body: some View {
        Menu {
            Section(tr("LRC 檔")) {
                Button { open() } label: { Label(tr("打開 LRC"), systemImage: "doc.badge.arrow.up") }
                // (the file made only when asked for, not every time the menu is drawn)
                Button { share = ShareItem(url: lrcFile) } label: { Label(tr("分享 LRC"), systemImage: "square.and.arrow.up") }
            }
            if page == 1 {
                Section(tr("對時間")) {
                    Picker(tr("按的時候提早"), selection: $reaction) {
                        Text(tr("不提早")).tag(0.0)
                        Text("0.1 s").tag(0.1)
                        Text("0.15 s").tag(0.15)
                        Text("0.2 s").tag(0.2)
                        Text("0.3 s").tag(0.3)
                    }
                    Button {
                        m.remember()
                        for i in m.lines.indices { m.lines[i].t = nil }
                        m.cursor = 0
                        m.focus = nil
                        SongPlayer.shared.seek(0)
                    } label: { Label(tr("全部重新對時"), systemImage: "arrow.counterclockwise") }
                }
            }
            if own.get(song.id) != nil {
                Button(role: .destructive) { delete() } label: { Label(tr("刪除自己的歌詞"), systemImage: "trash") }
            }
        } label: { Image(systemName: "ellipsis.circle").font(.system(size: 20)) }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
    }

    /// the lyrics as an .lrc file, named the way the 歌詞 folder names them (so it can be put there); on the 歌詞
    /// part, from the words as typed
    private var lrcFile: URL {
        let lines = page == 0 ? LRC.lines(fromText: m.text, keeping: m.lines) : m.lines
        let x = OwnLyric(trackId: song.id, trackName: song.trackName, artistName: song.artistName, duration: song.seconds,
                         lrc: LRC.make(lines, title: song.trackName, artist: song.artistName, length: song.seconds))
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(OwnLyrics.fileName(x))
        try? Data(x.lrc.utf8).write(to: u, options: .atomic)
        return u
    }
}

/// 打開 LRC: an .lrc file's words and times into the editor
private struct LRCOpener: ViewModifier {
    @Binding var open: Bool
    let song: SongHit
    let m: LyricsEditModel
    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $open, allowedContentTypes: [UTType(filenameExtension: "lrc") ?? .plainText, .plainText, .text]) { r in
            guard case .success(let url) = r else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: url), let text = String(data: d, encoding: .utf8) else { return }
            let x = OwnLyrics.fromLRC(text, trackId: song.id, date: Date())
            m.lines = LRC.lines(from: x.hit)
            m.text = m.lines.map(\.text).joined(separator: "\n")
        }
    }
}

/// the song in the editor: cover, name, play / pause, back 5 s, and a bar to drag anywhere in the song
private struct EditorPlayer: View {
    let song: SongHit
    @ObservedObject private var player = SongPlayer.shared
    @State private var dragging: Double?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                SongArt(url: song.art, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.trackName).ffFont(.subheadline, .semibold).lineLimit(1)
                    Text(song.artistName).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button { player.seek(max(0, (player.position ?? 0) - 5)) } label: { Text("−5 s").monospacedDigit() }
                    .softButton().accessibilityLabel(tr("倒退五秒"))
                Button { player.togglePause() } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 30, height: 26)
                }
                .softButton()
                .disabled(player.song?.id != song.id)
                .accessibilityLabel(player.playing ? tr("暫停") : tr("播放"))
            }
            if player.song?.id != song.id {
                Text(tr("這首歌沒有在放。到「音樂」放這首歌再來對時間。")).ffFont(.footnote).foregroundStyle(T.muted)
            } else {
                SongProgress(precise: true)
                if player.mode == .preview {
                    Text(tr("只有 30 秒的試聽：整首歌要有 Apple Music 才能對時間。")).ffFont(.caption).foregroundStyle(T.muted)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.7)))
    }
}

/// 歌詞對時, ② the timing: its own page. The player on top; every line with its time and −¼ / +¼ beside it; the
/// line being sung lit; at the bottom 退一行 · 這一句開始 · 空行 · 跳過
private struct LyricsTimingPage: View {
    let song: SongHit
    @ObservedObject var m: LyricsEditModel
    let close: () -> Void
    @ObservedObject private var own = OwnLyrics.shared
    @Environment(\.dismiss) private var back
    /// how much earlier than the tap the line starts (people tap a little late)
    @AppStorage("lrcReaction") private var reaction = 0.15
    @State private var confirmDelete = false

    private var player: SongPlayer { SongPlayer.shared }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    ForEach(m.lines.indices, id: \.self) { i in
                        row(i)
                            .id(i)
                            .listRowBackground(i == m.cursor ? T.btnEdge.opacity(0.28) : (i == m.focus ? T.fn.opacity(0.9) : Color.clear))
                            .swipeActions {
                                Button { m.remember(); m.lines[i].t = nil; m.lines[i].words = nil; if i < m.cursor { m.cursor = i } } label: { Label(tr("清掉時間"), systemImage: "clock.badge.xmark") }
                                if m.lines[i].text.isEmpty {
                                    Button(role: .destructive) { removeLine(i) } label: { Label(tr("刪除"), systemImage: "trash") }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: m.cursor) { _, c in withAnimation { proxy.scrollTo(min(c, max(0, m.lines.count - 1)), anchor: .center) } }
                .onChange(of: m.sung) { _, s in
                    // (playing through lines already timed: the list follows the song)
                    if let s, player.playing, m.cursor >= m.lines.count || s >= m.cursor { withAnimation { proxy.scrollTo(s, anchor: .center) } }
                }
            }
            tapBar
        }
    }

    private func row(_ i: Int) -> some View {
        let l = m.lines[i]
        return VStack(alignment: .leading, spacing: 6) {
            lineRow(i)
            // (the line being worked on: its words, to move where each starts)
            if m.picked == i, let t = l.t, !l.text.isEmpty, LRC.pieces(l.text).count >= 2 {
                WordTimingBar(m: m, i: i, start: t, end: endTime(i))
                    .padding(.leading, 60)
                    .padding(.bottom, 4)
            }
        }
    }

    /// where line i stops being sung: the next line's time (a 間奏 counts), else a few seconds on
    private func endTime(_ i: Int) -> Double {
        let t = m.lines[i].t ?? 0
        if i + 1 < m.lines.count, let n = m.lines[(i + 1)...].first(where: { $0.t != nil })?.t, n > t + 0.2 { return n }
        return t + 4
    }

    private func lineRow(_ i: Int) -> some View {
        let l = m.lines[i]
        let sung = m.sung == i
        return HStack(spacing: 8) {
            Text(l.t.map(LRC.shown) ?? "–")
                .ffFont(.caption).monospacedDigit()
                .foregroundStyle(l.t == nil ? T.muted.opacity(0.6) : T.muted)
                .frame(minWidth: 52, alignment: .leading)
            Group {
                if l.text.isEmpty {
                    Text(tr("（間奏）")).foregroundStyle(T.muted).italic()
                } else if sung, let t = l.t {
                    // (the line being sung: its words light up as they're sung, by its word times or spread evenly)
                    SungLineText(text: l.text, start: t, end: m.endOf(i), words: l.words)
                } else {
                    Text(l.text)
                        .foregroundStyle(l.t == nil ? T.glyph.opacity(0.6) : T.glyph)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // (one tap: this line is the one to work on; two: the song goes to it)
            .onTapGesture(count: 2) { jump(i) }
            .onTapGesture { pick(i) }
            if i == m.cursor { Image(systemName: "hand.tap").foregroundStyle(T.btnInk).ffFont(.caption) }
            // −¼ / +¼: this line a quarter of a second earlier or later (the song goes back to just before it)
            if l.t != nil {
                Button { move(i, -0.25) } label: { Text("−¼").monospacedDigit().frame(minWidth: 34, minHeight: 30) }
                    .softButton()
                    .accessibilityLabel(tr("這一行早四分之一秒"))
                Button { move(i, 0.25) } label: { Text("+¼").monospacedDigit().frame(minWidth: 34, minHeight: 30) }
                    .softButton()
                    .accessibilityLabel(tr("這一行晚四分之一秒"))
            }
        }
        .padding(.vertical, 2)
    }

    private func move(_ i: Int, _ d: Double) {
        guard let t = m.lines[i].t else { return }
        m.remember()
        m.lines[i].t = max(0, ((t + d) * 100).rounded() / 100)
        m.shiftWords(i, by: (m.lines[i].t ?? t) - t)
        m.focus = i
        m.picked = i
        player.seek(max(0, (m.lines[i].t ?? 0) - 1.5))
    }

    /// a line tapped once: the one to work on (the next tap times it, 空行 goes under it); the song stays where it is
    private func pick(_ i: Int) {
        m.cursor = i
        m.focus = i
        m.picked = i
    }

    /// a line tapped twice: the song goes to it (a little before its time, or the line before's when it has none)
    private func jump(_ i: Int) {
        pick(i)
        let at = m.lines[i].t ?? (i > 0 ? m.lines[i - 1].t : nil)
        if let a = at { player.seek(max(0, a - 1)) }
    }

    private var tapBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { undo() } label: {
                    Image(systemName: "backward.end").frame(width: 44, height: 52)
                }
                .softButton()
                .disabled(m.cursor == 0)
                .accessibilityLabel(tr("退一行"))
                Button { tap() } label: {
                    VStack(spacing: 2) {
                        Text(m.cursor < m.lines.count ? tr("這一句開始") : tr("對好了")).ffFont(.headline)
                        if m.cursor < m.lines.count {
                            Text(m.lines[m.cursor].text.isEmpty ? trs("（間奏）") : m.lines[m.cursor].text)
                                .ffFont(.caption).lineLimit(1).opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .softButton()
                .disabled(m.cursor >= m.lines.count || player.song?.id != song.id)
                Button { addBreak() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "return")
                        Text(tr("空行")).ffFont(.caption2)
                    }
                    .frame(width: 48, height: 52)
                }
                .softButton()
                .disabled(m.lines.isEmpty)
                .accessibilityLabel(tr("在這一行下面加一個空行"))
                // 重複這一句: the line chosen (or being sung) over and over, to time it
                Button {
                    if m.loopLine != nil { m.loopLine = nil }
                    else if let l = m.picked ?? m.focus ?? m.sung, m.lines.indices.contains(l), m.lines[l].t != nil { m.loopLine = l }
                } label: {
                    Image(systemName: m.loopLine != nil ? "repeat.circle.fill" : "repeat").frame(width: 44, height: 52)
                        .foregroundStyle(m.loopLine != nil ? T.btnInk : T.glyph)
                }
                .softButton()
                .accessibilityLabel(m.loopLine != nil ? tr("不要重複") : tr("重複這一句"))
                Button { skip() } label: {
                    Image(systemName: "forward.end").frame(width: 44, height: 52)
                }
                .softButton()
                .disabled(m.cursor >= m.lines.count)
                .accessibilityLabel(tr("跳過這一行"))
            }
            Text(tr("每一句開始唱的時候按「這一句開始」。放歌的時候按「空行」：唱著的那一行在這裡結束。點一下一行：改那一行（空行加在它下面）；點兩下：歌跳到那裡。−¼／+¼ 微調那一行；上面的 ↶ 復原。"))
                .ffFont(.caption2).foregroundStyle(T.muted)
        }
        .frame(maxWidth: 900)
        .padding()
        .frame(maxWidth: .infinity)
        .background(T.fn.opacity(0.6))
    }

    private func tap() {
        guard m.cursor < m.lines.count, let now = player.position else { return }
        m.remember()
        m.picked = nil
        let was = m.lines[m.cursor].t
        m.lines[m.cursor].t = max(0, ((now - reaction) * 100).rounded() / 100)
        if let was { m.shiftWords(m.cursor, by: (m.lines[m.cursor].t ?? was) - was) } else { m.lines[m.cursor].words = nil }
        m.focus = m.cursor
        m.cursor += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func undo() {
        guard m.cursor > 0 else { return }
        m.remember()
        m.cursor -= 1
        m.lines[m.cursor].t = nil
        m.lines[m.cursor].words = nil
        m.focus = nil
        player.seek(max(0, ((m.cursor > 0 ? m.lines[m.cursor - 1].t : nil) ?? 0) - 1))
    }

    /// 空行. While the song plays: the line being sung ends now (a timed blank line right under it). Paused: a
    /// blank line under the line tapped (or the one just timed), timed by the next tap.
    private func addBreak() {
        guard !m.lines.isEmpty else { return }
        m.remember()
        // (a line chosen by tapping it: under that one, whether the song plays or not)
        if let p = m.picked, m.lines.indices.contains(p) {
            let at = p + 1
            let t: Double? = player.playing ? player.position.map { max(0, (($0 - reaction) * 100).rounded() / 100) } : nil
            if at < m.lines.count && m.lines[at].text.isEmpty {
                if let t { m.lines[at].t = t }
            } else {
                m.lines.insert(TimedLine(text: "", t: t), at: at)
                if m.cursor >= at { m.cursor += 1 }
            }
            m.focus = at
            m.picked = nil
            m.cursor = t == nil ? at : min(m.lines.count, at + 1)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        if player.playing, let now = player.position {
            let t = max(0, ((now - reaction) * 100).rounded() / 100)
            // (the line being sung: by the times, or the one just timed)
            let on = m.sung ?? max(0, m.cursor - 1)
            let at = min(m.lines.count, on + 1)
            if at < m.lines.count && m.lines[at].text.isEmpty {
                m.lines[at].t = t
            } else {
                m.lines.insert(TimedLine(text: "", t: t), at: at)
                if m.cursor >= at { m.cursor += 1 }
                if let f = m.focus, f >= at { m.focus = f + 1 }
            }
            if m.cursor == at { m.cursor += 1 }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        let on = m.focus ?? max(0, m.cursor - 1)
        let at = min(m.lines.count, on + 1)
        // (already a blank line there, not timed yet: that one)
        if at < m.lines.count && m.lines[at].text.isEmpty && m.lines[at].t == nil { m.cursor = at; return }
        m.lines.insert(TimedLine(text: "", t: nil), at: at)
        if let f = m.focus, f >= at { m.focus = f + 1 }
        m.cursor = at
    }

    private func removeLine(_ i: Int) {
        m.remember()
        m.picked = nil
        m.lines.remove(at: i)
        if m.cursor > i { m.cursor -= 1 }
        if let f = m.focus { m.focus = f == i ? nil : (f > i ? f - 1 : f) }
    }

    private func skip() {
        guard m.cursor < m.lines.count else { return }
        m.remember()
        m.cursor += 1
    }

    private func clearTimes() {
        for i in m.lines.indices { m.lines[i].t = nil }
        m.cursor = 0
        m.focus = nil
        player.seek(0)
    }

    private var lrc: String { LRC.make(m.lines, title: song.trackName, artist: song.artistName, length: song.seconds) }

    private func save() {
        m.save(song)
        close()
    }
}

/// opens 歌詞對時 for the song playing
struct LyricsEditButton: View {
    @ObservedObject private var player = SongPlayer.shared
    @ObservedObject private var own = OwnLyrics.shared
    var label = false
    /// (the lyrics' tools strip: a plain round button)
    var plain = false
    /// (the lyrics page: it opens the editor itself; a button in its swiped bar, measured twice by ViewThatFits,
    /// opening a full page of its own froze the app)
    var onOpen: ((SongHit) -> Void)? = nil
    @State private var open = false
    var body: some View {
        if let s = player.song {
            Group {
                if label {
                    Button { open = true } label: {
                        Label(own.get(s.id) != nil ? tr("改自己的歌詞") : tr("自己打歌詞、對時間"), systemImage: "pencil.and.list.clipboard")
                    }
                } else if plain {
                    Button { if let onOpen { onOpen(s) } else { open = true } } label: { Image(systemName: "pencil.and.list.clipboard").toolCircle() }
                        .buttonStyle(.plain)
                } else {
                    Button { open = true } label: { Image(systemName: "pencil.and.list.clipboard") }
                        .softButton()
                }
            }
            .accessibilityLabel(tr("自己打歌詞、對時間"))
            // (a page of its own over the whole app: nothing else is drawn or moving behind it)
            .fullScreenCover(isPresented: $open) {
                LyricsEditor(song: s)
                    .environmentObject(Store.shared)
                    .preferredColorScheme(.dark)
                    .tint(AppTint.accent)
            }
        }
    }
}

/// under the line being worked on: its words in a bar, each as wide as the time it's sung. Drag the lines between
/// them: where the singer goes fast the words get narrow (the lyrics swell through them faster there).
private struct WordTimingBar: View {
    @ObservedObject var m: LyricsEditModel
    let i: Int
    let start: Double
    let end: Double
    /// the word times when the drag began (kept while dragging)
    @State private var dragFrom: [Double]?
    @State private var dragging: Int?

    private var pieces: [String] { LRC.pieces(m.lines[i].text) }

    /// the line's word times: the ones moved by hand, or spread evenly by the letters
    private var times: [Double] {
        let ps = pieces
        if let w = m.lines[i].words, w.count == ps.count { return w }
        let starts = LRC.pieceStarts(ps)
        let total = Double(max(1, ps.reduce(0) { $0 + $1.filter { $0.isLetter || $0.isNumber }.count }))
        return starts.map { start + (end - start) * Double($0) / total }
    }

    var body: some View {
        let ps = pieces
        let ts = times
        let span = max(0.2, end - start)
        let avg = span / Double(max(1, ps.count))
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                let x: (Double) -> CGFloat = { CGFloat(($0 - start) / span) * w }
                ZStack(alignment: .topLeading) {
                    ForEach(ps.indices, id: \.self) { k in
                        let a = ts[k], b = k + 1 < ts.count ? ts[k + 1] : end
                        let fast = (b - a) < avg * 0.6
                        Text(ps[k].trimmingCharacters(in: .whitespaces))
                            .ffFont(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .foregroundStyle(fast ? T.btnInk : T.glyph)
                            .frame(width: max(2, x(b) - x(a) - 2), height: 40)
                            .background(RoundedRectangle(cornerRadius: 6).fill(fast ? T.btnEdge.opacity(0.55) : T.fn.opacity(k % 2 == 0 ? 0.95 : 0.6)))
                            .offset(x: x(a) + 1)
                    }
                    // (the lines between the words: drag them)
                    ForEach(1..<max(1, ps.count), id: \.self) { k in
                        Capsule()
                            .fill(dragging == k ? T.btnInk : T.muted)
                            .frame(width: dragging == k ? 4 : 3, height: 48)
                            .frame(width: 24, height: 48)
                            .contentShape(Rectangle())
                            .offset(x: x(ts[k]) - 12, y: -4)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { v in drag(k, by: Double(v.translation.width / max(1, w)) * span) }
                                    .onEnded { _ in dragFrom = nil; dragging = nil; m.shareWords(from: i) }
                            )
                            .accessibilityLabel(tr("這個字開始的時候"))
                    }
                }
            }
            .frame(height: 40)
            HStack(spacing: 10) {
                Text(dragging.map { LRC.shown(ts[$0]) } ?? LRC.shown(start))
                    .ffFont(.caption2).monospacedDigit().foregroundStyle(T.muted)
                Spacer()
                Button { listen() } label: { Label(tr("聽這一句"), systemImage: "play.fill").ffFont(.caption) }
                    .softButton()
                Button { m.loopLine = m.loopLine == i ? nil : i } label: {
                    Label(tr("重複這一句"), systemImage: "repeat").ffFont(.caption)
                        .foregroundStyle(m.loopLine == i ? T.btnInk : T.glyph)
                }
                .softButton()
                .accessibilityAddTraits(m.loopLine == i ? .isSelected : [])
                if m.lines[i].words != nil {
                    Button { m.remember(); m.lines[i].words = nil } label: { Label(tr("平均"), systemImage: "equal").ffFont(.caption) }
                        .softButton()
                        .accessibilityLabel(tr("每個字一樣快"))
                }
                Text(LRC.shown(end)).ffFont(.caption2).monospacedDigit().foregroundStyle(T.muted)
            }
            Text(tr("拖字中間的線：唱得快的地方字就窄，歌詞變大的時候就照這個走。一模一樣的句子還沒有自己的時間的，會跟著一起改。"))
                .ffFont(.caption2).foregroundStyle(T.muted)
        }
    }

    /// line k (where piece k starts) moved; it stays between its neighbours
    private func drag(_ k: Int, by d: Double) {
        if dragFrom == nil {
            m.remember()
            dragFrom = times
            dragging = k
        }
        guard var w = dragFrom, w.indices.contains(k) else { return }
        let lo = w[k - 1] + 0.05
        let hi = (k + 1 < w.count ? w[k + 1] : end) - 0.05
        guard hi > lo else { return }
        w[k] = ((min(hi, max(lo, w[k] + d))) * 100).rounded() / 100
        w[0] = start
        if m.lines[i].words != w { m.lines[i].words = w }
    }

    private func listen() {
        let p = SongPlayer.shared
        p.seek(max(0, start - 0.5))
        if !p.playing { p.togglePause() }
    }
}

/// the line being sung in 對時間: the words already sung lit, the one being sung brightest, the rest dim. Only this
/// one line follows the song closely (ten times a second), not the whole list.
private struct SungLineText: View {
    let text: String
    let start: Double
    let end: Double
    let words: [Double]?

    var body: some View {
        let ps = LRC.pieces(text)
        let ts: [Double] = {
            if let w = words, w.count == ps.count { return w }
            let starts = LRC.pieceStarts(ps)
            let total = Double(max(1, ps.reduce(0) { $0 + $1.filter { $0.isLetter || $0.isNumber }.count }))
            return starts.map { start + (end - start) * Double($0) / total }
        }()
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let pos = SongPlayer.shared.position ?? 0
            let cur = ts.lastIndex(where: { $0 <= pos }) ?? -1
            ps.indices.reduce(Text("")) { acc, k in
                let piece = Text(ps[k])
                if k == cur { return acc + piece.foregroundColor(T.btnInk).fontWeight(.bold) }
                if k < cur { return acc + piece.foregroundColor(T.btnInk.opacity(0.75)).fontWeight(.semibold) }
                return acc + piece.foregroundColor(T.glyph.opacity(0.55))
            }
        }
    }
}
