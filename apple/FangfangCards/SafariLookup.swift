import SwiftUI

// Safari 查詞 (the Safari extension in FangfangSafari/): hover over a word with the Apple Pencil in Safari, and a card
// with its 華語 and 台語 words pops up. Its words are inside the extension (made on the Mac by install.sh, like the
// rest of the word data), and its own 設定 chooses the spellings, so it needs no shared folder with the app — it works
// however the app was installed, also with Sideloadly.
// The words chosen there (加到不熟 / 收藏) come here when its 傳到 App button opens
//   fangfangcards://safari?ops=<base64url of [[key, "u" | "s", the sentence on the page (optional)], …]>
// A word of a language the app can't open right now (a 華語 word while 台語 is on show) waits until it can.

@MainActor
enum SafariImport {
    private static let pendingKey = "safariPending"

    /// the words of a fangfangcards:// link: taken over (returns how many)
    @discardableResult
    static func handle(_ url: URL, _ store: Store) -> Int {
        guard url.scheme == "fangfangcards",
              let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "ops" })?.value
        else { return 0 }
        var b = q.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let data = Data(base64Encoded: b),
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
