import Foundation
import SwiftUI

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

    func set(_ x: OwnLyric) { items[x.trackId] = x; write() }

    func remove(_ trackId: Int) { items[trackId] = nil; write() }

    private func write() {
        if let d = try? JSONEncoder().encode(Array(items.values)) { try? d.write(to: file, options: .atomic) }
    }
}

/// one line while timing (text "" is a break between lines, 間奏)
struct TimedLine: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var t: Double?
}

enum LRC {
    /// 1:23.45 → "[01:23.45]"
    static func stamp(_ t: Double) -> String {
        let cs = Int((max(0, t) * 100).rounded())
        return String(format: "[%02d:%02d.%02d]", cs / 6000, (cs / 100) % 60, cs % 100)
    }

    /// "1:23.4" for showing
    static func shown(_ t: Double) -> String {
        let ds = Int((max(0, t) * 10).rounded())
        return String(format: "%d:%02d.%d", ds / 600, (ds / 10) % 60, ds % 10)
    }

    /// the lines written out as LRC. Lines without a time get one between their neighbours'; breaks without one are left out.
    static func make(_ lines: [TimedLine], title: String, artist: String, length: Double?) -> String {
        var ls = lines.filter { !($0.text.isEmpty && $0.t == nil) }
        // (untimed lines: spread evenly between the timed ones around them)
        var i = 0
        while i < ls.count {
            if ls[i].t != nil { i += 1; continue }
            var j = i
            while j < ls.count && ls[j].t == nil { j += 1 }
            let before = i > 0 ? ls[i - 1].t ?? 0 : 0
            let after = j < ls.count ? ls[j].t ?? (before + Double(j - i + 1) * 3) : before + Double(j - i + 1) * 3
            let step = (after - before) / Double(j - i + 1)
            for k in i..<j { ls[k].t = before + step * Double(k - i + 1) }
            i = j
        }
        var out = ["[ti:\(title)]", "[ar:\(artist)]"]
        if let l = length, l > 0 { out.append(String(format: "[length:%02d:%02d]", Int(l) / 60, Int(l) % 60)) }
        out.append("[by:方方詞卡]")
        for l in ls { out.append(stamp(l.t ?? 0) + l.text) }
        return out.joined(separator: "\n")
    }

    /// LRC (or LRCLIB's lyrics) → the lines with their times, breaks included
    static func lines(from h: LyricHit) -> [TimedLine] {
        if let rows = h.timedRows {
            var out: [TimedLine] = []
            for r in rows {
                for t in r.times { out.append(TimedLine(text: r.text, t: t)) }
            }
            out.sort { ($0.t ?? 0) < ($1.t ?? 0) }
            while out.first?.text.isEmpty == true { out.removeFirst() }
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
        while out.last?.text.isEmpty == true { out.removeLast() }
        for i in out.indices where i < old.count && old[i].text == out[i].text { out[i].t = old[i].t }
        return out
    }
}

/// 歌詞對時: ① the words (type, paste, or LRCLIB's to fix), ② tap along with the song, ③ save
struct LyricsEditor: View {
    let song: SongHit
    @ObservedObject private var player = SongPlayer.shared
    @ObservedObject private var own = OwnLyrics.shared
    @Environment(\.dismiss) private var dismiss
    /// how much earlier than the tap the line starts (people tap a little late)
    @AppStorage("lrcReaction") private var reaction = 0.15
    @State private var step = 0
    @State private var text = ""
    @State private var lines: [TimedLine] = []
    /// the line the next tap times
    @State private var cursor = 0
    /// the line the ± buttons move (the one just timed, or one tapped in the list)
    @State private var focus: Int?
    @State private var confirmDelete = false
    @State private var saved = false

    var body: some View {
        Group {
            if step == 0 { textStep } else { timingStep }
        }
        .appBackground()
        .navigationTitle(step == 0 ? tr("歌詞") : tr("對時間"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button(tr("取消")) { dismiss() } }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if step == 0 {
                    Button(tr("下一步")) { toTiming() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Menu {
                        Picker(tr("按的時候提早"), selection: $reaction) {
                            Text(tr("不提早")).tag(0.0)
                            Text("0.1 s").tag(0.1)
                            Text("0.15 s").tag(0.15)
                            Text("0.2 s").tag(0.2)
                            Text("0.3 s").tag(0.3)
                        }
                        Button { clearTimes() } label: { Label(tr("全部重新對時"), systemImage: "arrow.counterclockwise") }
                        ShareLink(item: lrc, preview: SharePreview(song.trackName + ".lrc")) {
                            Label(tr("分享 LRC"), systemImage: "square.and.arrow.up")
                        }
                        if own.get(song.id) != nil {
                            Button(role: .destructive) { confirmDelete = true } label: { Label(tr("刪除自己的歌詞"), systemImage: "trash") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    Button { text = lines.map(\.text).joined(separator: "\n"); step = 0 } label: { Image(systemName: "text.cursor") }
                        .accessibilityLabel(tr("改歌詞的字"))
                    Button(tr("儲存")) { save() }.fontWeight(.semibold)
                }
            }
        }
        .confirmationDialog(tr("刪除自己的歌詞？之後會用 LRCLIB 的歌詞。"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("刪除"), role: .destructive) {
                own.remove(song.id)
                if player.song?.id == song.id { player.reloadLyrics() }
                dismiss()
            }
        }
        .onAppear(perform: load)
        .onAppear { player.editing = true }
        .onDisappear { player.editing = false }
    }

    // MARK: ① the words

    private var textStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SongArt(url: song.art, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.trackName).ffFont(.subheadline, .semibold).lineLimit(1)
                    Text(song.artistName).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
                }
                Spacer()
                Button {
                    if let s = UIPasteboard.general.string { text = s }
                } label: { Label(tr("貼上"), systemImage: "doc.on.clipboard") }
                .softButton()
            }
            TextEditor(text: $text)
                .scaledFont(17)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
            Text(tr("一行一句。空一行是間奏（可以不對時間）。下一步一邊放歌，一邊在每一句開始唱的時候按一下。"))
                .ffFont(.footnote).foregroundStyle(T.muted)
        }
        .padding()
    }

    private func toTiming() {
        lines = LRC.lines(fromText: text, keeping: lines)
        cursor = lines.firstIndex(where: { $0.t == nil }) ?? lines.count
        focus = nil
        step = 1
        if player.song?.id == song.id && !player.playing && cursor == 0 { player.seek(0) }
    }

    // MARK: ② tap along

    private var timingStep: some View {
        VStack(spacing: 0) {
            controls
            ScrollViewReader { proxy in
                List {
                    ForEach(lines.indices, id: \.self) { i in
                        row(i)
                            .id(i)
                            .listRowBackground(i == cursor ? T.btnEdge.opacity(0.28) : (i == focus ? T.fn.opacity(0.9) : Color.clear))
                            .contentShape(Rectangle())
                            .onTapGesture { pick(i) }
                            .swipeActions {
                                Button { lines[i].t = nil; if i < cursor { cursor = i } } label: { Label(tr("清掉時間"), systemImage: "clock.badge.xmark") }
                                if lines[i].text.isEmpty {
                                    Button(role: .destructive) { removeLine(i) } label: { Label(tr("刪除"), systemImage: "trash") }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: cursor) { _, c in withAnimation { proxy.scrollTo(min(c, max(0, lines.count - 1)), anchor: .center) } }
            }
            tapBar
        }
    }

    /// the song: where it is, back a little, play / pause
    private var controls: some View {
        VStack(spacing: 6) {
            if player.song?.id != song.id {
                Text(tr("這首歌沒有在放。到「音樂」放這首歌再來對時間。")).ffFont(.footnote).foregroundStyle(T.muted)
            }
            HStack(spacing: 12) {
                Text(LRC.shown(player.time)).ffFont(.title3, .semibold).monospacedDigit()
                    .frame(minWidth: 74, alignment: .leading)
                Spacer()
                Button { player.seek(max(0, (player.position ?? 0) - 5)) } label: { Text("−5 s").monospacedDigit() }
                    .softButton().accessibilityLabel(tr("倒退五秒"))
                Button { player.seek(max(0, (player.position ?? 0) - 2)) } label: { Text("−2 s").monospacedDigit() }
                    .softButton().accessibilityLabel(tr("倒退兩秒"))
                Button { player.togglePause() } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 28)
                }
                .softButton()
                .accessibilityLabel(player.playing ? tr("暫停") : tr("播放"))
            }
            if player.mode == .preview {
                Text(tr("只有 30 秒的試聽：整首歌要有 Apple Music 才能對時間。")).ffFont(.caption).foregroundStyle(T.muted)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(T.fn.opacity(0.6))
    }

    private func row(_ i: Int) -> some View {
        let l = lines[i]
        let sung = nowLine == i
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(l.t.map(LRC.shown) ?? "–")
                .ffFont(.caption).monospacedDigit()
                .foregroundStyle(l.t == nil ? T.muted.opacity(0.6) : T.muted)
                .frame(minWidth: 52, alignment: .leading)
            if l.text.isEmpty {
                Text(tr("（間奏）")).foregroundStyle(T.muted).italic()
            } else {
                Text(l.text)
                    .foregroundStyle(sung ? T.btnInk : (l.t == nil ? T.glyph.opacity(0.6) : T.glyph))
                    .fontWeight(sung ? .semibold : .regular)
            }
            Spacer(minLength: 0)
            if i == cursor { Image(systemName: "hand.tap").foregroundStyle(T.btnInk).ffFont(.caption) }
        }
        .padding(.vertical, 2)
    }

    /// the line being sung now, by the times given so far
    private var nowLine: Int? {
        let t = player.time
        var best: Int?
        for (i, l) in lines.enumerated() { if let lt = l.t, lt <= t, best.map({ (lines[$0].t ?? 0) <= lt }) ?? true { best = i } }
        return best
    }

    /// a line tapped: time again from there (the song goes back to a little before it)
    private func pick(_ i: Int) {
        cursor = i
        focus = lines[i].t != nil ? i : nil
        let back = (i > 0 ? lines[i - 1].t : nil) ?? lines[i].t.map { $0 - 3 }
        if let b = back { player.seek(max(0, b - 1)) }
    }

    private var tapBar: some View {
        VStack(spacing: 8) {
            if let f = focus, lines.indices.contains(f), lines[f].t != nil {
                HStack(spacing: 8) {
                    Text(lines[f].text.isEmpty ? trs("（間奏）") : lines[f].text).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
                    Spacer(minLength: 4)
                    nudge("−0.1", -0.1)
                    nudge("−0.05", -0.05)
                    nudge("+0.05", 0.05)
                    nudge("+0.1", 0.1)
                }
            }
            HStack(spacing: 10) {
                Button { undo() } label: {
                    Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 52)
                }
                .softButton()
                .disabled(cursor == 0)
                .accessibilityLabel(tr("退一行"))
                Button { tap() } label: {
                    VStack(spacing: 2) {
                        Text(cursor < lines.count ? tr("這一句開始") : tr("對好了")).ffFont(.headline)
                        if cursor < lines.count {
                            Text(lines[cursor].text.isEmpty ? trs("（間奏）") : lines[cursor].text)
                                .ffFont(.caption).lineLimit(1).opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .softButton()
                .disabled(cursor >= lines.count || player.song?.id != song.id)
                // 空行: a blank line under the line you're on, to time as the next one (where a line stops being sung)
                Button { addBreak() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "return")
                        Text(tr("空行")).ffFont(.caption2)
                    }
                    .frame(width: 48, height: 52)
                }
                .softButton()
                .disabled(lines.isEmpty)
                .accessibilityLabel(tr("在這一行下面加一個空行"))
                Button { skip() } label: {
                    Image(systemName: "forward.end").frame(width: 44, height: 52)
                }
                .softButton()
                .disabled(cursor >= lines.count)
                .accessibilityLabel(tr("跳過這一行"))
            }
            Text(tr("每一句開始唱的時候按「這一句開始」。按錯了：退一行，或點那一行從那裡重新對。點過的那一行可以用 ± 微調。"))
                .ffFont(.caption2).foregroundStyle(T.muted)
        }
        .padding()
        .background(T.fn.opacity(0.6))
    }

    private func nudge(_ label: String, _ d: Double) -> some View {
        Button {
            if let f = focus, let t = lines[f].t {
                lines[f].t = max(0, ((t + d) * 100).rounded() / 100)
                player.seek(max(0, (lines[f].t ?? 0) - 1.5))
            }
        } label: { Text(label).ffFont(.caption, .semibold).monospacedDigit().frame(minWidth: 40, minHeight: 26) }
        .softButton()
    }

    private func tap() {
        guard cursor < lines.count, let now = player.position else { return }
        lines[cursor].t = max(0, ((now - reaction) * 100).rounded() / 100)
        focus = cursor
        cursor += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func undo() {
        guard cursor > 0 else { return }
        cursor -= 1
        lines[cursor].t = nil
        focus = nil
        player.seek(max(0, ((cursor > 0 ? lines[cursor - 1].t : nil) ?? 0) - 1))
    }

    /// the line you're on: the one just timed (or tapped in the list); before any, the first
    private var currentLine: Int { focus ?? max(0, cursor - 1) }

    /// a blank line right under the line you're on; the next tap times it
    private func addBreak() {
        guard !lines.isEmpty else { return }
        let at = min(lines.count, currentLine + 1)
        // (already a blank line there, not timed yet: that one)
        if at < lines.count && lines[at].text.isEmpty && lines[at].t == nil { cursor = at; return }
        lines.insert(TimedLine(text: "", t: nil), at: at)
        if let f = focus, f >= at { focus = f + 1 }
        cursor = at
    }

    private func removeLine(_ i: Int) {
        lines.remove(at: i)
        if cursor > i { cursor -= 1 }
        if let f = focus { focus = f == i ? nil : (f > i ? f - 1 : f) }
    }

    private func skip() {
        guard cursor < lines.count else { return }
        cursor += 1
    }

    private func clearTimes() {
        for i in lines.indices { lines[i].t = nil }
        cursor = 0
        focus = nil
        player.seek(0)
    }

    // MARK: ③ saving

    private var lrc: String { LRC.make(lines, title: song.trackName, artist: song.artistName, length: song.seconds) }

    private func save() {
        let x = OwnLyric(trackId: song.id, trackName: song.trackName, artistName: song.artistName, duration: song.seconds, lrc: lrc)
        own.set(x)
        // (playing now: the lyrics follow the new times right away)
        if player.song?.id == song.id { LyricsBridge.shared.put(x.hit) }
        dismiss()
    }

    private func load() {
        guard lines.isEmpty && text.isEmpty else { return }
        if let o = own.get(song.id) {
            lines = LRC.lines(from: o.hit)
        } else if player.song?.id == song.id, let h = LyricsBridge.shared.song {
            // (LRCLIB's: to fix or time)
            lines = LRC.lines(from: h)
        }
        text = lines.map(\.text).joined(separator: "\n")
        // (already timed: straight to the times)
        if !lines.isEmpty && lines.contains(where: { $0.t != nil }) {
            step = 1
            cursor = lines.firstIndex(where: { $0.t == nil }) ?? lines.count
        }
    }
}

/// opens 歌詞對時 for the song playing
struct LyricsEditButton: View {
    @ObservedObject private var player = SongPlayer.shared
    @ObservedObject private var own = OwnLyrics.shared
    var label = false
    @State private var open = false
    var body: some View {
        if let s = player.song {
            Group {
                if label {
                    Button { open = true } label: {
                        Label(own.get(s.id) != nil ? tr("改自己的歌詞") : tr("自己打歌詞、對時間"), systemImage: "pencil.and.list.clipboard")
                    }
                } else {
                    Button { open = true } label: { Image(systemName: "pencil.and.list.clipboard") }
                        .softButton()
                }
            }
            .accessibilityLabel(tr("自己打歌詞、對時間"))
            .sheet(isPresented: $open) {
                NavigationStack { LyricsEditor(song: s) }
                    .environmentObject(Store.shared)
                    .preferredColorScheme(.dark)
                    .tint(AppTint.accent)
                    .interactiveDismissDisabled()
            }
        }
    }
}
