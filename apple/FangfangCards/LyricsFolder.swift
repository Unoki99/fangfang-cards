import Foundation
import SwiftUI
import UniformTypeIdentifiers

// 選自己的歌詞: the lyrics of your own the app already keeps (made for 找歌來聽's songs, and those that came from
// the backup folder's 歌詞), and the other .lrc files in that folder (the computer version's for YouTube videos,
// "… [yt-abc123].lrc"), to choose from for the song playing (a YouTube video too). And the lyrics chosen by hand for
// a YouTube video, kept for it.

/// one file in the 歌詞 folder
struct LyricsFolderFile: Identifiable, Hashable {
    /// the file's name
    let id: String
    let title: String
    let artist: String
    let text: String
    var timed: Bool { text.range(of: #"\[\d+:\d+"#, options: .regularExpression) != nil }

    /// as lyrics to show (an id of its own from the file's name, the same each time)
    var hit: LyricHit {
        var h: UInt64 = 5381
        for b in id.utf8 { h = (h &* 33) &+ UInt64(b) }
        let n = -(Int(h % 900_000_000) + 1_000_000_000)
        return LyricHit(id: n, trackName: title, artistName: artist, duration: nil,
                        plain: timed ? nil : text, synced: timed ? text : nil)
    }
}

@MainActor
enum LyricsFolder {
    /// the files (by name), or why there are none to show
    static func files() -> (files: [LyricsFolderFile], problem: String?) {
        guard let folder = Store.shared.backupFolderURL else { return ([], nil) }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let dir = folder.appendingPathComponent(OwnLyrics.folderName, isDirectory: true)
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return ([], nil) }
        var out: [LyricsFolderFile] = []
        var waiting = 0
        for n in names {
            if n.hasPrefix(".") && n.hasSuffix(".icloud") {
                // (not downloaded yet: fetched, for the next time the list is opened)
                let real = String(n.dropFirst().dropLast(".icloud".count))
                if real.lowercased().hasSuffix(".lrc") {
                    try? fm.startDownloadingUbiquitousItem(at: dir.appendingPathComponent(real))
                    waiting += 1
                }
                continue
            }
            // (the app's own lyrics are listed from the app: not twice)
            if let id = OwnLyrics.trackId(of: n), OwnLyrics.shared.get(id) != nil { continue }
            guard n.lowercased().hasSuffix(".lrc"), let d = read(dir.appendingPathComponent(n)),
                  let text = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .utf16) else { continue }
            out.append(file(n, text))
        }
        out.sort { ($0.title + $0.artist).localizedStandardCompare($1.title + $1.artist) == .orderedAscending }
        let note: String? = waiting > 0 ? trs("還有 \(waiting) 個檔案在 iCloud 上，正在下載，等一下再打開看看。") : nil
        return (out, note)
    }

    /// the computer version's lyrics for this YouTube video ("… [yt-<video>].lrc"), if the folder has them
    static func forVideo(_ id: String) -> LyricHit? {
        guard !id.isEmpty, let folder = Store.shared.backupFolderURL else { return nil }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let dir = folder.appendingPathComponent(OwnLyrics.folderName, isDirectory: true)
        let tag = "[yt-" + id + "].lrc"
        guard let n = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.first(where: { $0.hasSuffix(tag) }),
              let d = read(dir.appendingPathComponent(n)), let text = String(data: d, encoding: .utf8) else { return nil }
        return file(n, text).hit
    }

    /// "繁華夢 - 黃齡 [1234567].lrc" → 繁華夢, 黃齡 (the file's [ti:] and [ar:] when it has them)
    private static func file(_ n: String, _ text: String) -> LyricsFolderFile {
        var base = String(n.dropLast(4))
        if let r = base.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) { base.removeSubrange(r) }
        let parts = base.components(separatedBy: " - ")
        var title = parts.first?.trimmingCharacters(in: .whitespaces) ?? base
        var artist = parts.count > 1 ? parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces) : ""
        if let t = tag("ti", text), !t.isEmpty { title = t }
        if let a = tag("ar", text), !a.isEmpty { artist = a }
        return LyricsFolderFile(id: n, title: title.isEmpty ? base : title, artist: artist, text: text)
    }

    private static func tag(_ k: String, _ text: String) -> String? {
        guard let r = text.range(of: "[" + k + ":") else { return nil }
        let rest = text[r.upperBound...]
        guard let end = rest.firstIndex(of: "]") else { return nil }
        return String(rest[..<end]).trimmingCharacters(in: .whitespaces)
    }

    private static func read(_ url: URL) -> Data? {
        var out: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in out = try? Data(contentsOf: u) }
        return out
    }
}

/// the lyrics chosen by hand for YouTube songs, by the video and by the song's name (the same song in another
/// video gets them too), on this device. Your own lyrics are kept as which they are (so changing them shows here)
@MainActor
enum YtPicks {
    private struct Kept: Codable {
        var id: Int
        var title: String
        var artist: String
        var duration: Double?
        var plain: String?
        var synced: String?
        /// your own lyrics (OwnLyrics' song number)
        var own: Int?
    }

    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("yt-lyrics.json")
    }

    /// "v:<video>" and "n:<the song's name>"
    private static var all: [String: Kept] = {
        guard let d = try? Data(contentsOf: file), let x = try? JSONDecoder().decode([String: Kept].self, from: d) else { return [:] }
        return x
    }()

    /// a video's name without "Official MV" and the like, made plain: the same song's name whatever the video
    static func nameKey(_ title: String) -> String {
        SongPlayer.norm(YtPlayer.queries(title, "", false).first ?? title)
    }

    static func get(video: String, title: String) -> LyricHit? {
        let n = nameKey(title)
        guard let k = all["v:" + video] ?? (n.isEmpty ? nil : all["n:" + n]) else { return nil }
        if let o = k.own { return OwnLyrics.shared.get(o)?.hit }
        return LyricHit(id: k.id, trackName: k.title, artistName: k.artist, duration: k.duration, plain: k.plain, synced: k.synced)
    }

    static func set(video: String, title: String, _ h: LyricHit) {
        let own: Int? = h.id < 0 && OwnLyrics.shared.get(-h.id) != nil ? -h.id : nil
        let k = Kept(id: h.id, title: h.trackName, artist: h.artistName, duration: h.duration,
                     plain: own == nil ? h.plainLyrics : nil, synced: own == nil ? h.syncedLyrics : nil, own: own)
        if !video.isEmpty { all["v:" + video] = k }
        let n = nameKey(title)
        if !n.isEmpty { all["n:" + n] = k }
        if let d = try? JSONEncoder().encode(all) { try? d.write(to: file, options: .atomic) }
    }

    /// your own lyrics whose song's name is in the video's name (the singer too, when it's given: those first)
    static func ownMatch(title: String, artist: String) -> LyricHit? {
        let t = SongPlayer.norm(title), a = SongPlayer.norm(artist)
        guard !t.isEmpty else { return nil }
        // (worked out in a plain loop: SongPlayer.norm belongs to the main actor, like this)
        var best: OwnLyric?
        var bestScore = -1
        for x in OwnLyrics.shared.items.values {
            let n = SongPlayer.norm(x.trackName)
            guard n.count >= 2, t.contains(n) else { continue }
            let ar = SongPlayer.norm(x.artistName)
            let score = n.count + (!ar.isEmpty && (t.contains(ar) || a.contains(ar)) ? 100 : 0)
            if score > bestScore { best = x; bestScore = score }
        }
        return best?.hit
    }
}

/// 選自己的歌詞: your own lyrics (the app's, as in 找歌來聽), then the 歌詞 folder's other files; searchable. One
/// chosen shows for the song playing
struct LyricsFolderPicker: View {
    let onPick: (LyricHit) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lyrics = LyricsBridge.shared
    @ObservedObject private var own = OwnLyrics.shared
    @State private var files: [LyricsFolderFile] = []
    @State private var problem: String?
    @State private var query = ""

    private func matches(_ t: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || t.lowercased().contains(q)
    }

    private var mine: [OwnLyric] {
        own.items.values.filter { matches($0.trackName + " " + $0.artistName) }
            .sorted { ($0.trackName + $0.artistName).localizedStandardCompare($1.trackName + $1.artistName) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                TextField(tr("歌名或歌手"), text: $query).autocorrectionDisabled()
            }
            Section(tr("自己的歌詞")) {
                if own.items.isEmpty { Text(tr("還沒有自己的歌詞。")).foregroundStyle(T.muted) }
                ForEach(mine, id: \.trackId) { x in
                    row(x.hit, x.trackName, x.artistName)
                }
            }
            let more = files.filter { matches($0.title + " " + $0.artist + " " + $0.id) }
            if !more.isEmpty || problem != nil {
                Section {
                    if let p = problem { Text(p).foregroundStyle(T.muted) }
                    ForEach(more) { f in
                        row(f.hit, f.title, f.artist.isEmpty ? f.id : f.artist + (f.timed ? "" : " · " + trs("沒有時間")))
                    }
                } header: {
                    Text(tr("歌詞資料夾裡的其他檔案"))
                } footer: {
                    Text(tr("備份資料夾裡「歌詞」的其他 .lrc 檔，例如電腦版替 YouTube 影片存的歌詞。")).ffFont(.footnote)
                }
            }
            Section {
            } footer: {
                Text(tr("YouTube 的影片選了歌詞以後，下次放同一首歌（同一部影片，或歌名一樣的別的影片）會自己用。")).ffFont(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("選自己的歌詞"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("完成")) { dismiss() } } }
        .task {
            let r = LyricsFolder.files()
            files = r.files; problem = r.problem
        }
    }

    private func row(_ h: LyricHit, _ title: String, _ detail: String) -> some View {
        Button { onPick(h); dismiss() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(T.glyph).lineLimit(1)
                    if !detail.isEmpty { Text(detail).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1) }
                }
                Spacer()
                if lyrics.song?.id == h.id { Image(systemName: "checkmark").foregroundStyle(T.btnInk) }
            }
        }
    }
}

/// the lyrics page's share button: 打開 LRC 檔 (for the song playing: 找歌來聽's song keeps them as your own lyrics, a
/// YouTube song keeps them for its video and name) and 分享 LRC 檔 (the lyrics shown, as an .lrc file)
struct LyricsFileMenu: View {
    let hit: LyricHit
    @State private var importing = false
    @State private var share: ShareItem?
    @State private var problem: String?

    var body: some View {
        Menu {
            Button { importing = true } label: { Label(tr("打開 LRC 檔"), systemImage: "doc.badge.arrow.up") }
            Button { share = ShareItem(url: file) } label: { Label(tr("分享 LRC 檔"), systemImage: "square.and.arrow.up") }
        } label: {
            Image(systemName: "square.and.arrow.up").toolCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("分享"))
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "lrc") ?? .plainText, .plainText, .text]) { r in
            guard case .success(let url) = r else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: url),
                  let text = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .utf16), !text.isEmpty else {
                problem = trs("讀不到這個檔案。"); return
            }
            Self.use(text, name: url.lastPathComponent)
        }
        .alert(problem ?? "", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button(tr("好")) { problem = nil }
        }
    }

    /// an .lrc file's lyrics for the song playing
    @MainActor static func use(_ text: String, name: String) {
        let b = LyricsBridge.shared
        if let s = SongPlayer.shared.song {
            // (找歌來聽: your own lyrics for this song, as the editor saves them)
            var x = OwnLyrics.fromLRC(text, trackId: s.id, date: Date())
            if x.trackName.isEmpty { x.trackName = s.trackName }
            if x.artistName.isEmpty { x.artistName = s.artistName }
            if x.duration == nil { x.duration = s.seconds }
            OwnLyrics.shared.set(x)
            b.put(x.hit)
            return
        }
        let h = LyricsFolderFile(id: name, title: name, artist: "", text: text)
        let shown = LyricHit(id: h.hit.id, trackName: YtPlayer.shared.now?.title ?? String(name.dropLast(name.lowercased().hasSuffix(".lrc") ? 4 : 0)),
                             artistName: YtPlayer.shared.now?.artist ?? "", duration: nil,
                             plain: h.timed ? nil : text, synced: h.timed ? text : nil)
        b.put(shown)
        // (a YouTube song: kept for its video and name)
        YtPlayer.shared.remember(shown)
    }

    /// the lyrics shown as an .lrc file ("繁華夢 - 黃齡.lrc"), made when asked for
    private var file: URL {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r")
        let clean = { (s: String) in s.components(separatedBy: bad).joined(separator: " ").trimmingCharacters(in: .whitespaces) }
        var name = clean(hit.trackName)
        if !hit.artistName.isEmpty { name += " - " + clean(hit.artistName) }
        if name.isEmpty { name = "lyrics" }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".lrc")
        let text = hit.syncedLyrics ?? hit.plainLyrics ?? ""
        try? Data(text.utf8).write(to: u, options: .atomic)
        return u
    }
}
