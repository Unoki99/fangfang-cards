import Foundation
import SwiftUI
import WidgetKit

/// Keeps the 分類 widgets up to date: writes each 分類's words (in the chosen spelling and 腔口) and your
/// progress into the App Group folder, and takes over words saved on a widget.
@MainActor
enum WidgetBridge {
    /// words shown for 常用詞 (the widget's "all words" choice): the most common ones
    static let commonCount = 1000
    private static var building = false
    private static var stateTask: Task<Void, Never>?

    /// call when the app opens: apply the widget's 收藏 changes, then refresh what the widget shows
    static func appOpened(_ store: Store) {
        guard store.loaded, WidgetShared.folder != nil else { return }
        mergeInbox(store)
        writeState(store)
        rebuildIfNeeded(store)
    }

    /// 收藏 changes made on a widget → the app's 收藏
    static func mergeInbox(_ store: Store) {
        let ops = WidgetShared.inbox()
        guard !ops.isEmpty else { return }
        var waiting: [WidgetInboxOp] = []
        for op in ops {
            // (台語 and 華語 words: either language's cards)
            if let u = op.unknown {
                // 加到不熟 from Safari: a word of a language the app can't open right now waits in the inbox until it can
                guard let c = store.card(for: op.k) else { waiting.append(op); continue }
                if u, store.status(c) != 2 { store.mark(c, known: false, undoable: false) }
                else if !u, store.status(c) == 2 { store.forget(c) }
            } else if op.known == true {
                if let c = store.card(for: op.k), store.status(c) != 1 { store.mark(c, known: true, undoable: false) }
            } else if op.known == false {
                // ✓ taken back on the widget: back to 新詞
                if let c = store.card(for: op.k), store.status(c) == 1 { store.forget(c) }
            } else if store.isSaved(op.k) != op.save {
                store.toggleSaved(op.k)
            }
        }
        WidgetShared.write(waiting, "inbox.json")
        store.saveNow()
    }

    /// progress changed (a swipe…): written when the app goes to the background, or after half a minute
    /// without changes. Every swipe used to write all your words out and reload the widgets a second later, and
    /// iOS only lets widgets reload so many times a day
    static func progressChanged(_ store: Store) {
        dirty = true
        later(store, seconds: 30)
    }
    /// a widget setting changed (設定): shown a moment later
    static func settingsChanged(_ store: Store) {
        later(store, seconds: 1)
    }
    /// the app goes to the background: what changed, written now
    static func flush(_ store: Store) {
        guard dirty else { return }
        stateTask?.cancel()
        writeState(store)
    }
    private static var dirty = false
    private static func later(_ store: Store, seconds: Double) {
        stateTask?.cancel()
        stateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            writeState(store)
        }
    }

    static func writeState(_ store: Store) {
        guard store.loaded, WidgetShared.folder != nil else { return }
        dirty = false
        let d = UserDefaults.standard
        var st = WidgetState()
        st.rom = min(max(d.integer(forKey: "rom"), 0), 2)
        st.place = d.object(forKey: "place") as? Int ?? -1
        st.bg = d.object(forKey: "widgetBG") as? Double ?? 0.45
        st.saved = store.progress.saved.filter { $0.value > 0 }.map(\.key).sorted()
        st.known = store.progress.status.filter { $0.value == 1 }.map(\.key).sorted()
        st.unknown = store.progress.status.filter { $0.value == 2 }.map(\.key).sorted()
        // don't drop saves made on the widget that the app hasn't taken over yet
        if !WidgetShared.inbox().isEmpty { mergeInbox(store); st.saved = store.progress.saved.filter { $0.value > 0 }.map(\.key).sorted() }
        WidgetShared.write(st, "state.json")
        writeUnknown(store, st.unknown ?? [])
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// the 不熟 分類 (台語 and 華語): written again when the 不熟 words change
    private static var unknownStamp = ""
    private static var wordCache: [String: WidgetWord] = [:]
    private static var cacheStamp = ""
    private static func writeUnknown(_ store: Store, _ keys: [String]) {
        let place = UserDefaults.standard.object(forKey: "place") as? Int ?? -1
        let stamp = "\(keys.hashValue)|\(place)|\(store.zh != nil)|\(store.dict != nil)|\(ToneColors.system)|\(ToneColors.marks)|\(ToneColors.signature)|\(ZhMeaning.english)|\(Lang.zhRom)|\(Lang.zhPlace)"
        guard stamp != unknownStamp else { return }
        unknownStamp = stamp
        // the words already written out stay good while the settings stay the same
        let settings = stamp.split(separator: "|", maxSplits: 1).last.map(String.init) ?? ""
        if cacheStamp != settings { wordCache = [:]; cacheStamp = settings }
        // the newest 400 of each language
        let newest = store.progress.status.filter { $0.value == 2 }.map(\.key)
            .sorted { (store.progress.added[$0] ?? 0) > (store.progress.added[$1] ?? 0) }
        var tw: [WidgetWord] = [], zh: [WidgetWord] = []
        for k in newest {
            let isZh = Lang.isZhKey(k)
            if isZh ? zh.count >= 400 : tw.count >= 400 { continue }
            if isZh && store.zh == nil { continue }
            guard let c = store.card(for: k) else { continue }
            let w: WidgetWord
            if let cached = wordCache[k] { w = cached }
            else { w = word(store, c, place) }
            wordCache[k] = w
            if isZh { zh.append(w) } else { tw.append(w) }
            if tw.count >= 400 && zh.count >= 400 { break }
        }
        WidgetShared.write(tw, WidgetShared.categoryFile(WidgetCat.twUnknown))
        WidgetShared.write(zh, WidgetShared.categoryFile(WidgetCat.zhUnknown))
        var list = WidgetShared.categories()
        if !list.isEmpty {
            for (id, n) in [(WidgetCat.twUnknown, tw.count), (WidgetCat.zhUnknown, zh.count)] {
                if let i = list.firstIndex(where: { $0.i == id }) { list[i] = WidgetCategory(i: id, n: list[i].n, c: n) }
            }
            WidgetShared.write(list, "categories.json")
        }
    }

    /// the word files: written again when the 腔口 changes, the dictionary has loaded (for local readings
    /// in the example sentences), or the word list changed
    static func rebuildIfNeeded(_ store: Store) {
        guard store.loaded, !building, WidgetShared.folder != nil else { return }
        let place = UserDefaults.standard.object(forKey: "place") as? Int ?? -1
        if place >= 0 && store.dict == nil { store.loadDict() }    // finished later: called again then
        let tones = ToneColors.system
        if tones != 0 && store.dict == nil { store.loadDict() }    // tone colours need the dictionary: called again then
        let needsDict = place >= 0 || tones != 0
        let tw = store.twDeck, zh = store.zhDeck
        let stamp = "v3|\(tw.cards.count)|\(tw.cards.first?.k ?? "")|\(place)|\(needsDict && store.dict != nil)|\(tones)|\(ToneColors.marks)|\(ToneColors.signature)"
            + "|zh\(zh.cards.count)|\(store.zhList)|\(Lang.zhRom)|\(Lang.zhPlace)|\(ZhMeaning.english)"
        if WidgetShared.defaults?.string(forKey: "words-stamp") == stamp,
           WidgetShared.read([WidgetCategory].self, "categories.json") != nil { return }
        building = true
        Task { @MainActor in
            // 台語: the 分類 and the most common words
            var byCat: [Int: [WidgetWord]] = [:]
            var common: [WidgetWord] = []
            for (i, c) in tw.cards.enumerated() {
                if i % 150 == 0 { await Task.yield() }
                let cats = c.cats ?? []
                guard !cats.isEmpty || i < commonCount else { continue }
                let w = word(store, c, place)
                for cat in cats { byCat[cat, default: []].append(w) }
                if i < commonCount { common.append(w) }
            }
            // 華語: each level of the word list, and each character level (not 更多常用字)
            for (i, c) in zh.cards.enumerated() {
                if i % 150 == 0 { await Task.yield() }
                guard let l = c.cats?.first, l != Lang.moreChars else { continue }
                byCat[WidgetCat.zhBase + l, default: []].append(word(store, c, place))
            }
            var list = [WidgetCategory(i: WidgetCat.common, n: "常用詞", c: common.count)]
            WidgetShared.write(common, WidgetShared.categoryFile(WidgetCat.common))
            list.append(WidgetCategory(i: WidgetCat.twUnknown, n: "不熟的詞（台語）", c: 0))
            for t in tw.topics {
                guard let ws = byCat[t.id], !ws.isEmpty else { continue }
                WidgetShared.write(ws, WidgetShared.categoryFile(t.id))
                list.append(WidgetCategory(i: t.id, n: t.name, c: ws.count))
            }
            if !zh.cards.isEmpty {
                list.append(WidgetCategory(i: WidgetCat.zhUnknown, n: "不熟的詞（華語）", c: 0))
                for t in zh.topics {
                    guard let ws = byCat[WidgetCat.zhBase + t.id], !ws.isEmpty else { continue }
                    WidgetShared.write(ws, WidgetShared.categoryFile(WidgetCat.zhBase + t.id))
                    list.append(WidgetCategory(i: WidgetCat.zhBase + t.id, n: "華語・" + t.name, c: ws.count))
                }
            }
            WidgetShared.write(list, "categories.json")
            unknownStamp = ""
            writeUnknown(store, store.progress.status.filter { $0.value == 2 }.map(\.key).sorted())
            WidgetShared.defaults?.set(stamp, forKey: "words-stamp")
            WidgetCenter.shared.reloadAllTimelines()
            building = false
            rebuildIfNeeded(store)          // the 腔口 or the dictionary changed meanwhile: once more
        }
    }

    /// one card as a widget word: the meaning that has an example sentence (so they match), in all spellings
    private static func word(_ store: Store, _ c: Card, _ place: Int) -> WidgetWord {
        let def = c.d.first(where: { !$0.x.isEmpty }) ?? c.d.first
        let x = def?.x.first
        let plain: (AttributedString) -> String = { String($0.characters) }
        let han = store.cardHan(c, place, base: T.blueInk)
        let rom = (0..<3).map { store.cardRom(c, $0, place) }
        let zy = store.cardZy(c, place)
        let xh = x.map { store.exampleHan(c, $0, place) }
        let xr = x.map { ex in (0..<3).map { store.exampleRom(c, ex, $0, place) } }
        // 華語: the other reading (注音 under 拼音, or 拼音 under 注音), its 詞類, and English as the meaning if chosen
        var z = plain(zy), p = def?.p ?? "", m = def?.t ?? ""
        if c.isZh, let d = store.zh {
            let syl = c.zhSyl(Lang.zhPlace) ?? []
            z = d.readingPlain(syl, Lang.zhRom == 0 ? 1 : 0)
            if let e = d.entry(c.k) {
                p = e.pos.joined(separator: "、")
                if ZhMeaning.english, !e.enList.isEmpty { m = e.enList.prefix(3).joined(separator: "; ") }
            }
        }
        var w = WidgetWord(
            k: c.k, h: c.h, a: c.a,
            r: rom.map(plain),
            z: z,
            p: p, m: m,
            xh: xh.map(plain),
            xr: xr.map { $0.map(plain) },
            xz: x?.z, xn: x?.n)
        w.hc = segs(han); w.rc = rom.map(segs); w.zc = segs(zy)
        w.xhc = xh.map(segs); w.xrc = xr.map { $0.map(segs) }
        return w
    }

    /// an AttributedString as pieces of one colour each (for the widget, which can't read SwiftUI colours)
    static func segs(_ a: AttributedString) -> [WSeg] {
        var out: [WSeg] = []
        let env = EnvironmentValues()
        for run in a.runs {
            let t = String(a[run.range].characters)
            var hex: String? = nil
            if let col = run.swiftUI.foregroundColor {
                let r = col.resolve(in: env)
                hex = String(format: "%02x%02x%02x", Int((r.red * 255).rounded()), Int((r.green * 255).rounded()), Int((r.blue * 255).rounded()))
            }
            if let last = out.last, last.c == hex { out[out.count - 1] = WSeg(t: last.t + t, c: hex) }
            else { out.append(WSeg(t: t, c: hex)) }
        }
        return out
    }
}
