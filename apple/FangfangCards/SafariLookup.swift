import SwiftUI

// Safari 查詞 (the Safari extension in FangfangSafari/): hover over a word with the Apple Pencil in Safari, and a card
// with its 華語 and 台語 words pops up. Its words are inside the extension (made on the Mac by install.sh, like the
// rest of the word data), and its own 設定 chooses the spellings, so it needs no shared folder with the app — it works
// however the app was installed, also with Sideloadly.
// The words chosen there (加到不熟 / 收藏) come here when its 傳到 App button opens
//   fangfangcards://safari?ops=<base64url of [[key, "u" | "s" | "k", the sentence on the page (optional)], …]>
//     ("u" 加到不熟, "s" 收藏, "k" 認識 → 熟悉)
//     &w=<base64url of {"2026-11-14": minutes watched with the subtitle panel, …}> (optional)
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
        guard let q = items.first(where: { $0.name == "ops" })?.value, let data = unpack(q),
              let ops = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { return 0 }
        var pending = UserDefaults.standard.array(forKey: pendingKey) as? [[String]] ?? []
        pending += ops.filter { $0.count >= 2 }
        UserDefaults.standard.set(pending, forKey: pendingKey)
        apply(store)
        return ops.count
    }

    /// the words waiting: put in where the app can (the rest keep waiting)
    static func apply(_ store: Store) {
        guard store.loaded else { return }
        let pending = UserDefaults.standard.array(forKey: pendingKey) as? [[String]] ?? []
        guard !pending.isEmpty else { return }
        var waiting: [[String]] = []
        for op in pending where op.count >= 2 {
            let k = op[0]
            // (the sentence on the page the word was saved from)
            if op.count >= 3 { store.addFoundSentence(k, op[2]) }
            if op[1] == "s" {
                if !store.isSaved(k) { store.toggleSaved(k) }
            } else if op[1] == "k" {
                // (認識 on Safari 查詞's card: 熟悉 here)
                if let c = store.card(for: k) { if store.status(c) != 1 { store.mark(c, known: true, undoable: false) } }
                else { waiting.append(op) }
            } else if let c = store.card(for: k) {
                if store.status(c) != 2 { store.mark(c, known: false, undoable: false) }
            } else {
                waiting.append(op)
            }
        }
        UserDefaults.standard.set(waiting, forKey: pendingKey)
        store.saveNow()
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
    static func payload(_ store: Store) -> (url: URL, known: Int, unknown: Int)? {
        let names = ["tw", "zh", "yue", "hak", "ja", "sv"]
        var known: [String: Set<String>] = [:], unknown: [String: Set<String>] = [:]
        for (k, st) in store.progress.status where st == 1 || st == 2 {
            let head = Lang.charOf(k) ?? String(k.split(separator: "\t", maxSplits: 1).first ?? "")
            guard !head.isEmpty else { continue }
            let l = names[min(max(Lang.kind(k), 0), names.count - 1)]
            if st == 1 { known[l, default: []].insert(head) } else { unknown[l, default: []].insert(head) }
        }
        let obj: [String: Any] = ["v": 1, "k": known.mapValues { Array($0) }, "u": unknown.mapValues { Array($0) }]
        guard let json = try? JSONSerialization.data(withJSONObject: obj),
              let packed = try? (json as NSData).compressed(using: .zlib) as Data else { return nil }
        let b = packed.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard let url = URL(string: "https://example.com/#fangfang-known=" + b) else { return nil }
        return (url, known.values.reduce(0) { $0 + $1.count }, unknown.values.reduce(0) { $0 + $1.count })
    }
}
