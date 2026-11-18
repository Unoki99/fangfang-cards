import Foundation
import SwiftUI
#if !targetEnvironment(macCatalyst)
import MediaPlayer
#endif

// 音樂: songs from Apple's catalogue (找歌來聽), kept apart from 電台 in the same window. Songs can be 收藏 (saved)
// and put in 歌單 (playlists); a list plays one song after the other. The lyrics show in 轉換 → 歌詞, like the radio's.

struct Playlist: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var songs: [SongHit] = []
}

/// 收藏的歌 and 歌單, kept on this device
@MainActor
final class MusicLibrary: ObservableObject {
    static let shared = MusicLibrary()
    private let key = "musicLibrary"
    @Published private(set) var saved: [SongHit] = []
    @Published private(set) var playlists: [Playlist] = []

    private struct Stored: Codable {
        var saved: [SongHit]
        var playlists: [Playlist]
    }

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(Stored.self, from: d) {
            saved = s.saved
            playlists = s.playlists
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(Stored(saved: saved, playlists: playlists)) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    // MARK: 收藏

    func isSaved(_ h: SongHit) -> Bool { saved.contains { $0.id == h.id } }

    func toggleSave(_ h: SongHit) {
        if isSaved(h) { saved.removeAll { $0.id == h.id } } else { saved.insert(h, at: 0) }
        save()
    }

    func removeSaved(at offsets: IndexSet) { saved.remove(atOffsets: offsets); save() }
    func moveSaved(from: IndexSet, to: Int) { saved.move(fromOffsets: from, toOffset: to); save() }

    // MARK: 歌單

    func playlist(_ id: String) -> Playlist? { playlists.first { $0.id == id } }

    @discardableResult
    func newPlaylist(_ name: String, with h: SongHit? = nil) -> String {
        newPlaylist(name, songs: h.map { [$0] } ?? [])
    }

    @discardableResult
    func newPlaylist(_ name: String, songs: [SongHit]) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<Int>()
        let p = Playlist(name: n.isEmpty ? trs("新歌單") : n, songs: songs.filter { seen.insert($0.id).inserted })
        playlists.append(p)
        save()
        return p.id
    }

    func contains(_ h: SongHit, in id: String) -> Bool { playlist(id)?.songs.contains { $0.id == h.id } ?? false }

    /// added at the end (once)
    func add(_ h: SongHit, to id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }), !playlists[i].songs.contains(where: { $0.id == h.id }) else { return }
        playlists[i].songs.append(h)
        save()
    }

    func remove(at offsets: IndexSet, from id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].songs.remove(atOffsets: offsets)
        save()
    }

    func move(from: IndexSet, to: Int, in id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].songs.move(fromOffsets: from, toOffset: to)
        save()
    }

    func rename(_ id: String, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = n
        save()
    }

    func deletePlaylists(at offsets: IndexSet) { playlists.remove(atOffsets: offsets); save() }
    func movePlaylists(from: IndexSet, to: Int) { playlists.move(fromOffsets: from, toOffset: to); save() }
}

// MARK: - 電台 / 音樂

/// the radio button's window: 電台 and 音樂, side by side like 詞典's sections
struct MediaTabs: View {
    /// 0 電台, 1 音樂
    @AppStorage("mediaTab") private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(tr("電台")).tag(0)
                Text(tr("音樂")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 6).padding(.bottom, 4)
            Group {
                if tab == 1 { MusicView() } else { RadioView() }
            }
            .frame(maxHeight: .infinity)
        }
        .appBackground()
    }
}

/// 音樂: the song playing, 找歌, 收藏的歌, 歌單
struct MusicView: View {
    @ObservedObject private var player = SongPlayer.shared
    @ObservedObject private var library = MusicLibrary.shared
    @ObservedObject private var lyrics = LyricsBridge.shared
    @State private var searching = false
    @State private var naming = false
    @State private var namingSong: SongHit?
    @State private var dragging: Double?
    @State private var importing = false

    var body: some View {
        List {
            nowSection
            Section {
                Button { searching = true } label: { Label(tr("找歌"), systemImage: "magnifyingglass") }
            } footer: {
                Text(tr("有 Apple Music 的話整首歌都可以聽，歌詞會自己跟著歌走。沒有的話可以聽 30 秒的試聽。歌來自 Apple 的音樂目錄，歌詞來自 LRCLIB。"))
                    .ffFont(.footnote)
            }
            Section {
                NavigationLink { SongListView(source: .saved) } label: {
                    HStack {
                        Label(tr("收藏的歌"), systemImage: "bookmark")
                        Spacer()
                        Text("\(library.saved.count)").foregroundStyle(T.muted).monospacedDigit()
                    }
                }
            }
            Section {
                ForEach(library.playlists) { p in
                    NavigationLink { SongListView(source: .playlist(p.id)) } label: {
                        HStack {
                            Label(p.name, systemImage: "music.note.list")
                            Spacer()
                            Text("\(p.songs.count)").foregroundStyle(T.muted).monospacedDigit()
                        }
                    }
                }
                .onDelete { library.deletePlaylists(at: $0) }
                .onMove { library.movePlaylists(from: $0, to: $1) }
                Button { namingSong = nil; naming = true } label: { Label(tr("新歌單"), systemImage: "plus") }
                #if !targetEnvironment(macCatalyst)
                Button { importing = true } label: { Label(tr("從 Apple Music 匯入歌單"), systemImage: "square.and.arrow.down") }
                #endif
            } header: {
                Text(tr("歌單"))
            } footer: {
                Text(tr("一首歌放完會接著放下一首。")).ffFont(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("音樂"))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(PlaylistNaming(open: $naming, song: namingSong))
        #if !targetEnvironment(macCatalyst)
        .sheet(isPresented: $importing) {
            NavigationStack { PlaylistImportView() }
                .environmentObject(Store.shared)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
        }
        #endif
        .sheet(isPresented: $searching) {
            NavigationStack { SongSearchView(jumpToLyrics: false) }
                .environmentObject(Store.shared)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
        }
    }

    @ViewBuilder private var nowSection: some View {
        if let s = player.song {
            Section {
                HStack(spacing: 12) {
                    SongArt(url: s.art, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.trackName).ffFont(.headline).lineLimit(2)
                        Text(player.mode == .preview ? s.artistName + " · " + trs("試聽") : s.artistName)
                            .ffFont(.subheadline).foregroundStyle(T.muted).lineLimit(1)
                        if player.queue.count > 1 {
                            Text(tr("第 \(player.index + 1) 首，共 \(player.queue.count) 首")).ffFont(.caption).foregroundStyle(T.muted)
                        }
                    }
                    Spacer(minLength: 4)
                    Button { library.toggleSave(s) } label: {
                        Image(systemName: library.isSaved(s) ? "bookmark.fill" : "bookmark").font(.system(size: 22))
                    }
                    .buttonStyle(.plain).foregroundStyle(T.btnInk)
                    .accessibilityLabel(library.isSaved(s) ? tr("取消收藏") : trSaveVerb())
                }
                .padding(.vertical, 4)
                // 上一首 · 播放 / 暫停 · 下一首
                HStack(spacing: 28) {
                    Spacer()
                    Button { player.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 22)) }
                        .accessibilityLabel(tr("上一首"))
                    Button { player.togglePause() } label: {
                        Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 44))
                    }
                    .accessibilityLabel(player.playing ? tr("暫停") : tr("播放"))
                    Button { player.next() } label: { Image(systemName: "forward.fill").font(.system(size: 22)) }
                        .disabled(!player.hasNext)
                        .opacity(player.hasNext ? 1 : 0.35)
                        .accessibilityLabel(tr("下一首"))
                    Spacer()
                }
                .buttonStyle(.plain).foregroundStyle(T.btnInk)
                SongProgress()
                if player.mode == .preview, let w = player.why {
                    Text(w).ffFont(.caption).foregroundStyle(T.muted)
                }
                // the lyrics: 轉換 → 歌詞, the same place as the radio's
                Button { LyricsBridge.showInConvert() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note.list").foregroundStyle(T.btnInk)
                        if let h = lyrics.song {
                            Text(tr("歌詞：\(h.trackName)")).lineLimit(1)
                        } else if lyrics.looking {
                            Text(tr("找歌詞…")).foregroundStyle(T.muted)
                        } else {
                            Text(tr("歌詞")).foregroundStyle(T.muted)
                        }
                    }
                }
                LyricsEditButton(label: true)
                Menu {
                    SongMenuItems(song: s, showSave: false) { namingSong = s; naming = true }
                } label: {
                    Label(tr("加到歌單"), systemImage: "text.badge.plus")
                }
                Button(role: .destructive) { player.stop() } label: { Label(tr("停止播放"), systemImage: "stop.fill") }
            } header: { Text(tr("正在聽")) }
        }
    }
}

/// 收藏的歌, or one 歌單: tap a song and the list plays from there
struct SongListView: View {
    enum Source: Hashable { case saved, playlist(String) }
    let source: Source
    @ObservedObject private var player = SongPlayer.shared
    @ObservedObject private var library = MusicLibrary.shared
    @State private var naming = false
    @State private var namingSong: SongHit?
    @State private var renaming = false
    @State private var newName = ""

    private var songs: [SongHit] {
        switch source {
        case .saved: return library.saved
        case .playlist(let id): return library.playlist(id)?.songs ?? []
        }
    }

    private var title: String {
        switch source {
        case .saved: return trs("收藏的歌")
        case .playlist(let id): return library.playlist(id)?.name ?? trs("歌單")
        }
    }

    var body: some View {
        List {
            if songs.isEmpty {
                Text(source == .saved
                     ? tr("還沒有收藏的歌。找歌的時候往右滑，或在正在聽的歌按書籤。")
                     : tr("這個歌單還沒有歌。找歌的時候長按一首歌，選「加到歌單」。"))
                    .foregroundStyle(T.muted)
            } else {
                Section {
                    Button {
                        if let f = songs.first { player.play(f, in: songs) }
                    } label: { Label(tr("全部播放"), systemImage: "play.fill") }
                    Button {
                        let mixed = songs.shuffled()
                        if let f = mixed.first { player.play(f, in: mixed) }
                    } label: { Label(tr("隨機播放"), systemImage: "shuffle") }
                }
                Section {
                    ForEach(songs) { h in
                        Button { player.play(h, in: songs) } label: { SongRow(song: h) }
                            .contextMenu { SongMenuItems(song: h) { namingSong = h; naming = true } }
                    }
                    .onDelete { offs in
                        switch source {
                        case .saved: library.removeSaved(at: offs)
                        case .playlist(let id): library.remove(at: offs, from: id)
                        }
                    }
                    .onMove { from, to in
                        switch source {
                        case .saved: library.moveSaved(from: from, to: to)
                        case .playlist(let id): library.move(from: from, to: to, in: id)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if case .playlist(let id) = source {
                    Button { newName = library.playlist(id)?.name ?? ""; renaming = true } label: { Image(systemName: "pencil") }
                        .accessibilityLabel(tr("改歌單名稱"))
                }
                if !songs.isEmpty { EditButton() }
            }
        }
        .modifier(PlaylistNaming(open: $naming, song: namingSong))
        .alert(tr("改歌單名稱"), isPresented: $renaming) {
            TextField(tr("歌單名稱"), text: $newName)
            Button(tr("好")) { if case .playlist(let id) = source { library.rename(id, to: newName) } }
            Button(tr("取消"), role: .cancel) {}
        }
    }
}

/// a song in a list: cover, name, singer · album · length; a sound mark on the one playing
struct SongRow: View {
    let song: SongHit
    @ObservedObject private var player = SongPlayer.shared
    var body: some View {
        HStack(spacing: 12) {
            SongArt(url: song.art, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.trackName).foregroundStyle(player.song?.id == song.id ? T.btnInk : T.glyph).lineLimit(1)
                Text(detail).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if player.song?.id == song.id {
                Image(systemName: player.playing ? "speaker.wave.2.fill" : "speaker.fill").foregroundStyle(T.btnInk)
            }
        }
    }
    private var detail: String {
        var p = [song.artistName]
        if let a = song.collectionName, !a.isEmpty, a != song.trackName { p.append(a) }
        if let d = song.seconds, d > 0 { p.append(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)) }
        return p.joined(separator: " · ")
    }
}

/// a song's menu: 收藏, 加到歌單 (each 歌單, or a new one)
struct SongMenuItems: View {
    let song: SongHit
    var showSave = true
    /// 新歌單… (the view showing the menu asks for the name)
    let onNew: () -> Void
    @ObservedObject private var library = MusicLibrary.shared
    var body: some View {
        if showSave {
            Button { library.toggleSave(song) } label: {
                Label(library.isSaved(song) ? tr("取消收藏") : trSaveVerb(), systemImage: library.isSaved(song) ? "bookmark.slash" : "bookmark")
            }
        }
        Menu {
            ForEach(library.playlists) { p in
                Button { library.add(song, to: p.id) } label: {
                    if library.contains(song, in: p.id) { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
            Divider()
            Button { onNew() } label: { Label(tr("新歌單…"), systemImage: "plus") }
        } label: {
            Label(tr("加到歌單"), systemImage: "text.badge.plus")
        }
    }
}

/// 新歌單: its name asked for (with the song to put in it first, if there is one)
struct PlaylistNaming: ViewModifier {
    @Binding var open: Bool
    var song: SongHit?
    @State private var name = ""
    func body(content: Content) -> some View {
        content.alert(tr("新歌單"), isPresented: $open) {
            TextField(tr("歌單名稱"), text: $name)
            Button(tr("建立")) { MusicLibrary.shared.newPlaylist(name, with: song); name = "" }
            Button(tr("取消"), role: .cancel) { name = "" }
        } message: {
            if let s = song { Text(tr("「\(s.trackName)」會放進去。")) }
        }
    }
}


#if !targetEnvironment(macCatalyst)
/// 從 Apple Music 匯入歌單: the playlists in your Apple Music library (the Music app's 資料庫), copied in here as 歌單
struct PlaylistImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lists: [MPMediaPlaylist] = []
    @State private var allowed: Bool?
    /// the playlists checked
    @State private var picked: Set<UInt64> = []
    @State private var working = false
    @State private var progress = ""
    @State private var done: [String] = []

    var body: some View {
        List {
            if allowed == false {
                Text(tr("方方詞卡還沒被允許用 Apple Music。到 設定 → 方方詞卡 → 媒體與 Apple Music 打開。")).foregroundStyle(T.muted)
                if let u = URL(string: UIApplication.openSettingsURLString) {
                    Button(tr("打開設定")) { UIApplication.shared.open(u) }
                }
            } else if allowed == true && lists.isEmpty {
                Text(tr("資料庫裡沒有歌單。在「音樂」App 把歌單加到資料庫，就會出現在這裡。")).foregroundStyle(T.muted)
            }
            if working {
                Section { HStack(spacing: 10) { ProgressView(); Text(progress).foregroundStyle(T.muted) } }
            } else if !done.isEmpty {
                Section { ForEach(done, id: \.self) { Text($0).foregroundStyle(T.btnInk) } }
            }
            if !lists.isEmpty {
                Section {
                    ForEach(lists, id: \.persistentID) { p in
                        Button { toggle(p.persistentID) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: picked.contains(p.persistentID) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(picked.contains(p.persistentID) ? T.btnInk : T.muted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name ?? trs("歌單")).foregroundStyle(T.glyph).lineLimit(1)
                                    Text(tr("\(p.count) 首")).ffFont(.caption).foregroundStyle(T.muted)
                                }
                                Spacer()
                            }
                        }
                        .disabled(working)
                    }
                } header: {
                    HStack {
                        Text(tr("勾選要匯入的歌單"))
                        Spacer()
                        Button(picked.count == lists.count ? tr("全部不選") : tr("全選")) {
                            picked = picked.count == lists.count ? [] : Set(lists.map(\.persistentID))
                        }
                        .textCase(nil)
                        .disabled(working)
                    }
                } footer: {
                    Text(tr("勾好按「匯入」，每個歌單都會變成這裡的歌單（之後在「音樂」改了，不會跟著變，可以再匯入一次）。只有 Apple Music 裡有的歌會帶過來，自己放進去的音樂檔不會。"))
                        .ffFont(.footnote)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("從 Apple Music 匯入歌單"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button(picked.isEmpty ? tr("匯入") : tr("匯入（\(picked.count)）")) { bring() }
                    .fontWeight(.semibold)
                    .disabled(picked.isEmpty || working)
            }
        }
        .task { await load() }
    }

    private func toggle(_ id: UInt64) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    private func load() async {
        var st = MPMediaLibrary.authorizationStatus()
        if st == .notDetermined {
            st = await withCheckedContinuation { (k: CheckedContinuation<MPMediaLibraryAuthorizationStatus, Never>) in
                MPMediaLibrary.requestAuthorization { k.resume(returning: $0) }
            }
        }
        guard st == .authorized else { allowed = false; return }
        allowed = true
        let found = (MPMediaQuery.playlists().collections ?? []).compactMap { $0 as? MPMediaPlaylist }
        lists = found.filter { $0.count > 0 }
    }

    /// each playlist checked: its songs by their Apple Music numbers, looked up in the catalogue, kept in their order
    private func bring() {
        let chosen = lists.filter { picked.contains($0.persistentID) }
        guard !chosen.isEmpty else { return }
        working = true
        done = []
        Task {
            let cc = await SongPlayer.shared.storeCountry()
            var out: [String] = []
            for (n, p) in chosen.enumerated() {
                let name = p.name ?? trs("歌單")
                progress = tr("匯入「\(name)」…（\(n + 1)/\(chosen.count)）")
                let ids = p.items.map(\.playbackStoreID).filter { $0 != "0" && !$0.isEmpty }
                let total = p.items.count
                guard let songs = try? await SongSource.lookup(ids, country: cc) else {
                    out.append(tr("「\(name)」：連不上，等一下再試試看。"))
                    continue
                }
                if songs.isEmpty {
                    out.append(tr("「\(name)」裡沒有 Apple Music 的歌可以帶過來。"))
                    continue
                }
                MusicLibrary.shared.newPlaylist(name, songs: songs)
                out.append(songs.count == total
                    ? tr("「\(name)」匯入了 \(songs.count) 首歌。")
                    : tr("「\(name)」匯入了 \(songs.count) 首歌（\(total - songs.count) 首不在 Apple Music 裡，沒有帶過來）。"))
            }
            done = out
            picked = []
            working = false
        }
    }
}
#endif
