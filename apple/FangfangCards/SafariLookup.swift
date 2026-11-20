import SwiftUI

// Safari 查詞 (the Safari extension in FangfangSafari/): hover over a word with the Apple Pencil in Safari, and a card
// with its 華語 and 台語 words pops up. Its words are inside the extension (made on the Mac by install.sh, like the
// rest of the word data), and its own 設定 chooses the spellings, so it needs no shared folder with the app — it works
// however the app was installed, also with Sideloadly.
// The words chosen there (加到不熟 / 收藏) come here when its 傳到 App button opens
//   fangfangcards://safari?ops=<base64url of [[key, "u" | "s" | "k", the sentence on the page (optional)], …]>
//     ("u" 加到不熟, "s" 收藏, "k" 認識 → 熟悉, "g" only into its 影片詞組: a word chosen before there were groups,
//      found again in its video's subtitles)
//     (a fourth: the 影片詞組 the word was chosen in, its id in gr)
//     &w=<base64url of {"2026-11-14": minutes watched with the subtitle panel, …}> (optional)
//     &gr=<base64url of {"yt:abc123": [the video's name, its address], …}> (optional: 影片詞組)
//     &vk=<base64url of {"yt:abc123": [the video's name, its address, 懂 %, when], …}> (optional: 影片懂多少)
// A word of a language the app can't open right now (a 華語 word while 台語 is on show) waits until it can.

@MainActor
enum SafariImport {
    private static let pendingKey = "safariPending"

    /// the words of a fangfangcards:// link: taken over (returns how many)
    @discardableResult
    static func handle(_ url: URL, _ store: Store) -> Int {
        guard url.scheme == "fangfangcards", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return 0 }
        func unpack(_ s: String) -> Data? {
            var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while b.count % 4 != 0 { b += "=" }
            return Data(base64Encoded: b)
        }
        // (練習統計: the minutes watched with the subtitle panel, by day)
        if let w = items.first(where: { $0.name == "w" })?.value, let d = unpack(w),
           let days = try? JSONSerialization.jsonObject(with: d) as? [String: Double] {
            for (day, m) in days { store.addListening(day: day, m, kind: 1) }
        }
        // (影片懂多少: each video's 懂 %, {"yt:abc123": [its name, address, %, when in seconds], …})
        if let vk = items.first(where: { $0.name == "vk" })?.value, let d = unpack(vk),
           let vids = try? JSONSerialization.jsonObject(with: d) as? [String: [Any]] {
            for (id, v) in vids where v.count >= 4 {
                store.noteSeen(id, name: v[0] as? String ?? "", url: v[1] as? String ?? "",
                               pct: (v[2] as? NSNumber)?.doubleValue ?? 0, at: (v[3] as? NSNumber)?.doubleValue ?? 0)
            }
        }
        guard let q = items.first(where: { $0.name == "ops" })?.value, let data = unpack(q),
              let ops = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { return 0 }
        // 影片詞組: the words chosen from one video go into its group (by their keys: a word waiting for its language
        // is in the group already). Not the ones marked 認識.
        let groups = items.first(where: { $0.name == "gr" })?.value.flatMap(unpack)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: [String]] } ?? [:]
        var pending = UserDefaults.standard.array(forKey: pendingKey) as? [[String]] ?? []
        pending += ops.filter { $0.count >= 2 }
        guard store.loaded else {
            // (not ready yet: the groups too wait, with their words)
            UserDefaults.standard.set(pending, forKey: pendingKey)
            for op in ops where op.count >= 4 && op[1] != "k" && !op[3].isEmpty {
                let g = groups[op[3]] ?? []
                store.addToGroup(op[3], name: g.first ?? op[3], url: g.count > 1 ? g[1] : "", key: op[0])
            }
            return ops.count
        }
        // (everything in one go: see Store.applySafari)
        let waiting = store.applySafari(groupOps: ops, groups: groups, ops: pending)
        UserDefaults.standard.set(waiting, forKey: pendingKey)
        return ops.count
    }

    /// the words waiting: put in where the app can (the rest keep waiting)
    static func apply(_ store: Store) {
        guard store.loaded else { return }
        let pending = UserDefaults.standard.array(forKey: pendingKey) as? [[String]] ?? []
        guard !pending.isEmpty else { return }
        let waiting = store.applySafari(groupOps: [], groups: [:], ops: pending)
        UserDefaults.standard.set(waiting, forKey: pendingKey)
    }

    static var waitingCount: Int { (UserDefaults.standard.array(forKey: pendingKey) as? [[String]] ?? []).count }
}

// MARK: - the words you know, to Safari 查詞

/// Safari 查詞 marks the words you don't know yet in the subtitle panel and tells how much of a video you
/// understand. It can't read the app's data (that would need a shared folder, which a Sideloadly install doesn't
/// have), so the app hands the words over through Safari: it opens example.com (a page kept by the internet's
/// standards body for examples) with the words after a "#", which never leaves the device; the extension, on that
/// page, keeps them and shows how many it got.
@MainActor
enum SafariKnownSync {
    /// the words: 認識 (status 1) and 不熟 (2), by language, as headwords
    /// (text: the same words to copy, for 貼上 on Safari 查詞's settings page when example.com doesn't work)
    static func payload(_ store: Store) -> (url: URL, known: Int, unknown: Int, text: String)? {
        let names = ["tw", "zh", "yue", "hak", "ja", "sv"]
        var known: [String: Set<String>] = [:], unknown: [String: Set<String>] = [:]
        for (k, st) in store.progress.status where st == 1 || st == 2 {
            let head = Lang.charOf(k) ?? String(k.split(separator: "\t", maxSplits: 1).first ?? "")
            guard !head.isEmpty else { continue }
            let l = names[min(max(Lang.kind(k), 0), names.count - 1)]
            if st == 1 { known[l, default: []].insert(head) } else { unknown[l, default: []].insert(head) }
        }
        // (the sentences 不熟 and 收藏 words were chosen from, of the words not in a 影片詞組 yet: Safari 查詞 finds them
        // again in a video's subtitles and puts those words in that video's group)
        var inGroup = Set<String>()
        for (wk, t) in store.progress.groupWords where t > 0 {
            if let r = wk.range(of: "\u{1}") { inGroup.insert(String(wk[r.upperBound...])) }
        }
        var found: [[String]] = []
        for (k, ss) in store.progress.found where !inGroup.contains(k) && (store.progress.status[k] == 2 || store.isSaved(k)) {
            for s in ss.suffix(3) where !s.isEmpty { found.append([k, s]) }
        }
        let obj: [String: Any] = ["v": 1, "k": known.mapValues { Array($0) }, "u": unknown.mapValues { Array($0) }, "f": found]
        guard let json = try? JSONSerialization.data(withJSONObject: obj),
              let packed = try? (json as NSData).compressed(using: .zlib) as Data else { return nil }
        let b = packed.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard let url = URL(string: "https://example.com/#fangfang-known=" + b) else { return nil }
        return (url, known.values.reduce(0) { $0 + $1.count }, unknown.values.reduce(0) { $0 + $1.count }, "fangfang-known:" + b)
    }
}
