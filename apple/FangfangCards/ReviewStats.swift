import SwiftUI

// MARK: - 複習 (spaced review) and 練習統計

/// the numbers of spaced review: a word learned in practice comes back after 1 day, then 3, then each time about
/// 2.5× longer ("ease"; a little less each time it's forgotten, never under 1.3). The way of SM-2:
/// Algorithm SM-2, (C) Copyright SuperMemo World, 1991. www.supermemo.com
enum SRS {
    static let ease = 2.5
    static let minEase = 1.3
    /// (at most about a year and a half between two reviews)
    static let longest = 540.0
    /// 記熟了: back in 3 weeks or more
    static let matureDays = 21.0
    static func days(_ d: Double) -> Double { d * 86_400 }

    /// "台語|2026-11-08" (the day where the device is)
    static func dayKey(_ lang: String, _ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%@|%04d-%02d-%02d", lang, c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// 不熟: how many words are due for review, and the button to the statistics
struct ReviewBar: View {
    /// the words due now (the same count as 練習統計's 要複習)
    let due: Int
    let stats: () -> Void
    /// 要複習 tapped: practise the words due (false: 一般練習, true: 手寫練習)
    var practise: (Bool) -> Void = { _ in }
    var body: some View {
        HStack(spacing: 10) {
            if due > 0 {
                // 要複習: straight into practising them
                Menu {
                    Button { practise(false) } label: { Label(tr("一般練習"), systemImage: "graduationcap") }
                    Button { practise(true) } label: { Label(tr("手寫練習"), systemImage: "pencil.and.scribble") }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(T.btnInk)
                        Text(tr("要複習")).foregroundStyle(T.glyph)
                        Text("\(due)").ffFont(.subheadline, .bold, mono: true).foregroundStyle(T.btnInk)
                        Image(systemName: "play.fill").font(.caption2).foregroundStyle(T.btnInk)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(T.btn))
                    .overlay(Capsule().stroke(T.btnEdge, lineWidth: 1.5))
                    .contentShape(Capsule())
                }
                .accessibilityLabel(tr("練習要複習的詞"))
            } else {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(T.btnInk)
                Text(tr("現在沒有要複習的詞")).foregroundStyle(T.muted)
            }
            Spacer(minLength: 4)
            Button(action: stats) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis").foregroundStyle(T.btnInk)
                    Text(tr("統計")).foregroundStyle(T.glyph)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .ffFont(.subheadline)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
    }
}

/// 練習統計: where the words of the language shown are, what's coming back when, and the answers of the last
/// 30 days
struct ReviewStatsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    private struct Counts { var unknown = 0, learning = 0, young = 0, mature = 0, due = 0, swiped = 0 }

    private var counts: Counts {
        var c = Counts()
        let now = Date().timeIntervalSince1970
        let p = store.progress
        for (k, st) in p.status where Lang.kind(k) == store.lang {
            if st == 2 { if (p.streak[k] ?? 0) > 0 { c.learning += 1 } else { c.unknown += 1 } }
            else if st == 1 {
                if let s = p.srs[k], s.count >= 2, s[1] >= 1 {
                    if s[1] >= SRS.matureDays { c.mature += 1 } else { c.young += 1 }
                    if s[0] <= now { c.due += 1 }
                } else { c.swiped += 1 }
            }
        }
        return c
    }

    /// the words coming back on each of the next 7 days (today: also the ones waiting)
    private var nextDays: [Int] {
        var out = Array(repeating: 0, count: 7)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let p = store.progress
        for (k, s) in p.srs where s.count >= 2 && s[1] >= 1 && p.status[k] == 1 && Lang.kind(k) == store.lang {
            let d = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: Date(timeIntervalSince1970: s[0]))).day ?? 0
            if d < 7 { out[max(0, d)] += 1 }
        }
        return out
    }

    /// right / wrong / learned on each of the last 30 days (oldest first)
    private var lastDays: [(right: Int, wrong: Int, learned: Int)] {
        let cal = Calendar.current
        let name = Lang.names[store.lang]
        return (0..<30).reversed().map { back in
            let d = cal.date(byAdding: .day, value: -back, to: Date()) ?? Date()
            let l = store.progress.log[SRS.dayKey(name, d)] ?? []
            return (l.count > 0 ? l[0] : 0, l.count > 1 ? l[1] : 0, l.count > 2 ? l[2] : 0)
        }
    }

    var body: some View {
        let c = counts
        let next = nextDays
        let last = lastDays
        let today = last.last ?? (0, 0, 0)
        let total = last.reduce(0) { $0 + $1.right + $1.wrong }
        let right = last.reduce(0) { $0 + $1.right }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // where the words are
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    tile(tr("要複習"), c.due, T.btnInk)
                    tile(tr("不熟"), c.unknown, T.rustInk)
                    tile(tr("學習中"), c.learning, T.oliveInk)
                    tile(tr("複習中"), c.young, T.blueInk)
                    tile(tr("記熟了"), c.mature, T.greenInk)
                    tile(tr("滑過去的熟悉"), c.swiped, T.muted)
                }
                Text(tr("學習中：答對過，還沒學會。複習中：練習學會的詞，會照時間回來複習。記熟了：三個禮拜以上才回來一次。滑過去的熟悉：在「新詞」往右滑的詞，不會回來複習。"))
                    .ffFont(.caption).foregroundStyle(T.muted)

                section(tr("今天")) {
                    HStack(spacing: 18) {
                        stat(tr("答對"), today.right, T.greenInk)
                        stat(tr("答錯"), today.wrong, T.rustInk)
                        stat(tr("學會"), today.learned, T.btnInk)
                    }
                }

                section(tr("接下來 7 天要複習的詞")) {
                    bars(next.map { (Double($0), 0) }, labels: (0..<7).map { $0 == 0 ? trs("今天") : dayLabel($0) }, showNumbers: true)
                }

                section(tr("最近 30 天的答題")) {
                    bars(last.map { (Double($0.right), Double($0.wrong)) }, labels: (0..<30).map { $0 % 7 == 2 ? dayLabel($0 - 29) : "" }, showNumbers: false)
                    HStack(spacing: 14) {
                        legend(T.greenInk, tr("答對")); legend(T.rustInk, tr("答錯"))
                        Spacer()
                        if total > 0 {
                            Text(tr("答對率 \(Int((Double(right) / Double(total) * 100).rounded()))%")).ffFont(.subheadline, .bold).foregroundStyle(T.glyph)
                        }
                    }
                }

                // listening: radio and videos, and the words picked up
                let lis = listenDays
                let todayL = lis.last ?? (0, 0, 0)
                section(tr("聽和看")) {
                    HStack(spacing: 18) {
                        stat(tr("電台（分鐘）"), Int(todayL.radio.rounded()), T.blueInk)
                        stat(tr("影片（分鐘）"), Int(todayL.video.rounded()), T.oliveInk)
                        stat(tr("今天存的詞"), todayL.words, T.greenInk)
                    }
                    bars(lis.map { ($0.radio, $0.video) }, labels: (0..<30).map { $0 % 7 == 2 ? dayLabel($0 - 29) : "" }, showNumbers: false,
                         colors: (T.blueInk, T.oliveInk))
                    HStack(spacing: 14) {
                        legend(T.blueInk, tr("電台")); legend(T.oliveInk, tr("影片字幕"))
                        Spacer()
                        Text(tr("30 天共 \(Int(lis.reduce(0) { $0 + $1.radio + $1.video }.rounded())) 分鐘")).ffFont(.subheadline, .bold).foregroundStyle(T.glyph)
                    }
                    Text(tr("影片的時間在 Safari 查詞按「傳到 App」的時候一起傳過來。")).ffFont(.caption).foregroundStyle(T.muted)
                }

                // every day you did something, the last 20 weeks (all languages)
                section(tr("學習日曆")) {
                    Heatmap(days: activity)
                    Text(tr("顏色越亮，那天做得越多：練習答題、聽電台、看影片字幕、存詞都算。")).ffFont(.caption).foregroundStyle(T.muted)
                }

                Text(tr("複習的間隔照 SM-2 的方法：學會以後 1 天、3 天，再來每次大約 2.5 倍；答錯就回到「不熟」重新學，以後的間隔也短一點。Algorithm SM-2, (C) Copyright SuperMemo World, 1991."))
                    .ffFont(.caption2).foregroundStyle(T.muted)
            }
            .padding()
        }
        .appBackground()
        .navigationTitle(tr("練習統計"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("完成")) { dismiss() } } }
    }

    private static func dayString(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// the last 30 days (oldest first): radio and video minutes, and the words added or saved
    private var listenDays: [(radio: Double, video: Double, words: Int)] {
        let cal = Calendar.current
        let p = store.progress
        var words: [String: Int] = [:]
        for t in p.added.values { words[Self.dayString(Date(timeIntervalSince1970: t)), default: 0] += 1 }
        for t in p.saved.values where t > 0 { words[Self.dayString(Date(timeIntervalSince1970: t)), default: 0] += 1 }
        return (0..<30).reversed().map { back in
            let d = Self.dayString(cal.date(byAdding: .day, value: -back, to: Date()) ?? Date())
            let l = p.listen[d] ?? []
            return (l.count > 0 ? l[0] : 0, l.count > 1 ? l[1] : 0, words[d] ?? 0)
        }
    }

    /// how much was done each day ("2026-11-14" → a number): answers + minutes listened + words
    private var activity: [String: Double] {
        let p = store.progress
        var a: [String: Double] = [:]
        for (k, v) in p.log {
            guard let day = k.split(separator: "|").last else { continue }
            a[String(day), default: 0] += Double((v.first ?? 0) + (v.count > 1 ? v[1] : 0))
        }
        for (d, v) in p.listen { a[d, default: 0] += v.reduce(0, +) }
        for t in p.added.values { a[Self.dayString(Date(timeIntervalSince1970: t)), default: 0] += 1 }
        for t in p.saved.values where t > 0 { a[Self.dayString(Date(timeIntervalSince1970: t)), default: 0] += 1 }
        return a
    }

    private func dayLabel(_ offset: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    private func tile(_ title: String, _ n: Int, _ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).ffFont(.footnote).foregroundStyle(T.muted)
            Text("\(n)").ffFont(.title2, .bold, mono: true).foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
    }

    private func stat(_ title: String, _ n: Int, _ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").ffFont(.title3, .bold, mono: true).foregroundStyle(ink)
            Text(title).ffFont(.caption).foregroundStyle(T.muted)
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10); Text(t).ffFont(.caption).foregroundStyle(T.muted) }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).ffFont(.subheadline, .bold).foregroundStyle(T.glyph)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.fnEdge, lineWidth: 1))
    }

    /// a bar for each value (a: green / the language's colour, b: red on top of it)
    /// (colors: the bottom part and the part on top; nil: answers, green and red)
    private func bars(_ values: [(Double, Double)], labels: [String], showNumbers: Bool, colors: (Color, Color)? = nil) -> some View {
        let top = max(1, values.map { $0.0 + $0.1 }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: values.count > 10 ? 3 : 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                VStack(spacing: 4) {
                    if showNumbers { Text(v.0 > 0 ? "\(Int(v.0))" : "").ffFont(.caption2, mono: true).foregroundStyle(T.muted) }
                    VStack(spacing: 0) {
                        if v.1 > 0 { Rectangle().fill(colors?.1 ?? T.rustInk).frame(height: 110 * v.1 / top) }
                        Rectangle().fill(colors?.0 ?? (showNumbers ? T.btnInk : T.greenInk)).frame(height: max(v.0 > 0 ? 2 : 0, 110 * v.0 / top))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(maxWidth: .infinity)
                    Text(labels[i]).ffFont(.caption2).foregroundStyle(T.muted).lineLimit(1).fixedSize()
                        .frame(height: 14)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: showNumbers ? 150 : 135, alignment: .bottom)
    }
}

/// 學習日曆: the last 20 weeks, a square a day (weeks across, Monday at the top), brighter for the days you did more
struct Heatmap: View {
    let days: [String: Double]
    private let weeks = 20

    var body: some View {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        // (Monday of this week)
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let start = cal.date(byAdding: .day, value: -wd - 7 * (weeks - 1), to: today) ?? today
        let top = max(1, days.values.max() ?? 1)
        GeometryReader { g in
            let size = min(18, (g.size.width - CGFloat(weeks - 1) * 3) / CGFloat(weeks))
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let date = cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? start
                            let v = days[Self.key(date)] ?? 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(date > today ? Color.clear : (v <= 0 ? T.fn : T.greenInk.opacity(0.25 + 0.75 * min(1, sqrt(v / top)))))
                                .frame(width: size, height: size)
                        }
                    }
                }
            }
        }
        .frame(height: 7 * 18 + 6 * 3)
    }
    private static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - 我的進度 (the profile page, from the button at the top left of the main pages)

/// the top-left button of the main pages: 我的進度
struct ProfileButton: View {
    var body: some View {
        Button { Router.shared.profileOpen = true } label: {
            Image(systemName: "person.crop.circle").foregroundStyle(T.glyph)
        }
        .accessibilityLabel(tr("我的進度"))
    }
}

/// 我的進度: everything about what you know and how you've been learning, in tiles (a grid on an iPad, one column on
/// a narrow phone)
struct ProfileView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                    tile(tr("認識的詞"), "checkmark.seal") { wordsTile }
                    if store.isZh || !store.freqTopics.isEmpty { tile(levelTitle, FrequencyRing.icon) { levelTile } }
                    tile(tr("最近 30 天的練習"), "graduationcap") { practiceTile }
                    tile(tr("聽的時間"), "headphones") { listenTile }
                    tile(tr("影片懂多少"), "play.rectangle") { videoTile }
                    tile(tr("複習"), "clock.arrow.circlepath") { reviewTile }
                }
                .padding()
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle(tr("我的進度"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } } }
        }
    }

    private func tile<C: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if icon == FrequencyRing.icon {
                    Label { Text(title) } icon: { FrequencyRingView(size: 17, line: 3, fill: 0.7) }
                } else {
                    Label(title, systemImage: icon)
                }
            }
            .ffFont(.headline).foregroundStyle(T.glyph)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(T.fn.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(T.fnEdge, lineWidth: 1))
    }

    private func big(_ n: String, _ label: String, _ c: Color = T.btnInk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(n).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(c).monospacedDigit()
            Text(label).ffFont(.caption).foregroundStyle(T.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── 認識的詞, by language ──
    private var wordsTile: some View {
        var known = Array(repeating: 0, count: Lang.names.count), unknown = known
        for (k, s) in store.progress.status {
            let l = min(max(Lang.kind(k), 0), Lang.names.count - 1)
            if s == 1 { known[l] += 1 } else if s == 2 { unknown[l] += 1 }
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                big("\(known.reduce(0, +))", trs("熟悉"))
                big("\(unknown.reduce(0, +))", trs("不熟"), T.oliveInk)
                big("\(store.progress.saved.values.filter { $0 > 0 }.count)", trs("收藏"), T.blueInk)
            }
            ForEach(Lang.names.indices, id: \.self) { l in
                if known[l] + unknown[l] > 0 {
                    HStack {
                        Text(trs(Lang.names[l])).ffFont(.subheadline, .semibold).frame(width: 60, alignment: .leading)
                        SplitPotionBar(known: Double(known[l]) / Double(known[l] + unknown[l]), unknown: Double(unknown[l]) / Double(known[l] + unknown[l]),
                                       label: Lang.names[l], tint: levelColor(l + 1))
                        Text("\(known[l])／\(unknown[l])").ffFont(.caption).monospacedDigit().foregroundStyle(T.muted)
                    }
                }
            }
        }
    }

    // ── HSK / TOCFL (華語) or 常用詞 (台語): each level, and the level you're at ──
    private var levelTitle: String {
        store.lang == 1 || store.isEn ? tr("\(Lang.listNames[min(max(store.zhList, 0), Lang.listNames.count - 1)]) 等級") : (store.isZh ? tr("常用詞") : tr("常用詞和常用字"))
    }

    private var levelTile: some View {
        let topics = store.isZh ? store.topics : store.freqTopics
        let all = store.allTopicProgress()
        let words = topics.filter { store.isZh ? $0.id < Lang.charTopicBase : $0.id < Lang.freqCharBase }
        let chars = topics.filter { store.isZh ? $0.id > Lang.charTopicBase : $0.id >= Lang.freqCharBase }
        // (the level you're at: the highest one whose words — and every one before it — you know 80% of)
        func reached(_ ts: [Topic]) -> String? {
            var last: String?
            for t in ts {
                let p = all[t.id] ?? (0, 0, 0)
                guard p.total > 0, Double(p.known) / Double(p.total) >= 0.8 else { break }
                last = t.name
            }
            return last
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                big(reached(words) ?? "—", trs("詞的等級"))
                if !chars.isEmpty { big(reached(chars) ?? "—", trs("字的等級"), T.blueInk) }
            }
            ForEach(words + chars) { t in
                let p = all[t.id] ?? (0, 0, 0)
                let k = p.total > 0 ? Double(p.known) / Double(p.total) : 0
                let u = p.total > 0 ? Double(p.unknown) / Double(p.total) : 0
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(t.name).ffFont(.caption, .semibold)
                        Spacer()
                        Text("\(Int((k * 100).rounded()))%").ffFont(.caption).monospacedDigit().foregroundStyle(levelColor(t.id))
                    }
                    SplitPotionBar(known: k, unknown: u, label: t.name, tint: levelColor(t.id))
                }
            }
            Text(tr("等級：那一級（和前面每一級）的詞你認識八成以上。")).ffFont(.caption2).foregroundStyle(T.muted)
        }
    }

    // ── practice, the last 30 days ──
    private var days: [Date] {
        let cal = Calendar.current
        return (0..<30).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: Date()) }
    }

    private var practiceTile: some View {
        let per = days.map { d -> (right: Int, wrong: Int, learned: Int) in
            var r = 0, w = 0, l = 0
            for n in Lang.names {
                let v = store.progress.log[SRS.dayKey(n, d)] ?? []
                r += v.count > 0 ? v[0] : 0; w += v.count > 1 ? v[1] : 0; l += v.count > 2 ? v[2] : 0
            }
            return (r, w, l)
        }
        let right = per.reduce(0) { $0 + $1.right }, wrong = per.reduce(0) { $0 + $1.wrong }
        let top = max(1, per.map { $0.right + $0.wrong }.max() ?? 1)
        // (days in a row with practice, up to today)
        // (today without practice yet doesn't break it)
        var streak = 0
        for (i, p) in per.reversed().enumerated() {
            if p.right + p.wrong > 0 { streak += 1 } else if i > 0 { break }
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                big("\(right + wrong)", trs("題"))
                big(right + wrong > 0 ? "\(Int((100 * Double(right) / Double(right + wrong)).rounded()))%" : "—", trs("答對"), T.oliveInk)
                big("\(per.reduce(0) { $0 + $1.learned })", trs("學會"), T.blueInk)
                big("\(streak)", trs("連續天數"), T.pinkInk)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(per.indices, id: \.self) { i in
                    VStack(spacing: 0) {
                        Rectangle().fill(T.muted.opacity(0.5)).frame(height: 60 * CGFloat(per[i].wrong) / CGFloat(top))
                        Rectangle().fill(T.btnEdge).frame(height: 60 * CGFloat(per[i].right) / CGFloat(top))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 60, alignment: .bottom)
                }
            }
            .frame(height: 60)
            Text(tr("綠：答對　灰：答錯（每一天一條，最右邊是今天）")).ffFont(.caption2).foregroundStyle(T.muted)
        }
    }

    // ── listening: the radio and videos (with the add-on's subtitle panel) ──
    private var listenTile: some View {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let per = days.map { store.progress.listen[f.string(from: $0)] ?? [0, 0] }
        let radio = per.reduce(0) { $0 + ($1.first ?? 0) }, video = per.reduce(0) { $0 + ($1.count > 1 ? $1[1] : 0) }
        let allTime = store.progress.listen.values.reduce(0) { $0 + $1.reduce(0, +) }
        let top = max(1, per.map { $0.reduce(0, +) }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                big("\(Int(radio.rounded()))", trs("分鐘電台"))
                big("\(Int(video.rounded()))", trs("分鐘影片"), T.blueInk)
                big("\(Int((allTime / 60).rounded()))", trs("小時（全部）"), T.oliveInk)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(per.indices, id: \.self) { i in
                    let r = per[i].first ?? 0, v = per[i].count > 1 ? per[i][1] : 0
                    VStack(spacing: 0) {
                        Rectangle().fill(T.blueEdge).frame(height: 60 * v / top)
                        Rectangle().fill(T.btnEdge).frame(height: 60 * r / top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 60, alignment: .bottom)
                }
            }
            .frame(height: 60)
            Text(tr("綠：電台　藍：影片（最近 30 天）")).ffFont(.caption2).foregroundStyle(T.muted)
        }
    }

    // ── videos: how much of each one's words you knew when you watched it (Safari 查詞's 懂 %), and of the words
    // you picked from it (影片詞組), how many you know now; oldest first ──
    private var videoTile: some View {
        var words: [String: [String]] = [:]
        for (wk, t) in store.progress.groupWords where t > 0 {
            guard let r = wk.range(of: "\u{1}") else { continue }
            words[String(wk[..<r.lowerBound]), default: []].append(String(wk[r.upperBound...]))
        }
        let seen = store.progress.seen.filter { $0.value.count >= 2 }
        var ids = Set(seen.keys)
        for (id, t) in store.progress.groupTime where t > 0 && !(words[id] ?? []).isEmpty { ids.insert(id) }
        let rows = ids.map { id -> (name: String, pct: Double?, k: Int, n: Int, date: Date) in
            let ws = words[id] ?? []
            let k = ws.filter { store.progress.status[$0] == 1 }.count
            let t = seen[id]?[1] ?? abs(store.progress.groupTime[id] ?? 0)
            return (store.groupName(id), seen[id].map { $0[0] / 100 }, k, ws.count, Date(timeIntervalSince1970: t))
        }.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Text(tr("還沒有影片。用查詞看影片字幕，再按「傳到 App」（或同步），就會有每個影片你懂多少。")).ffFont(.footnote).foregroundStyle(T.muted)
            } else {
                // (each video a bar: how much of it you understood; one with only picked words: how many of those you know, paler)
                let last = Array(rows.suffix(40))
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(last.indices, id: \.self) { i in
                        let r = last[i]
                        let v = r.pct ?? Double(r.k) / Double(max(1, r.n))
                        RoundedRectangle(cornerRadius: 2).fill(levelColor(Int(v * 7) + 1)).opacity(r.pct == nil ? 0.45 : 1)
                            .frame(maxWidth: .infinity).frame(height: max(3, 70 * v))
                    }
                }
                .frame(height: 70, alignment: .bottom)
                ForEach(Array(rows.suffix(6).reversed().enumerated()), id: \.offset) { _, r in
                    HStack {
                        Text(r.name).ffFont(.caption).lineLimit(1)
                        Spacer()
                        if r.n > 0 {
                            Text(trs("選的詞") + " \(r.k)/\(r.n)").ffFont(.caption2).foregroundStyle(T.muted).monospacedDigit()
                        }
                        Text(r.pct.map { trs("懂") + " \(Int(($0 * 100).rounded()))%" } ?? "—").ffFont(.caption, .semibold).monospacedDigit()
                        Text(r.date.formatted(date: .abbreviated, time: .omitted)).ffFont(.caption2).foregroundStyle(T.muted)
                    }
                }
                Text(tr("每一條是一個影片（從左到右，舊到新）：懂 = 看的時候字幕裡的詞你認識多少；選的詞 = 你從那裡選的詞，現在認識幾個。")).ffFont(.caption2).foregroundStyle(T.muted)
            }
        }
    }

    // ── spaced review ──
    private var reviewTile: some View {
        let srs = store.progress.srs.values.filter { $0.count >= 2 }
        let mature = srs.filter { $0[1] >= SRS.matureDays }.count
        let due = store.allDueCards.count
        return HStack {
            big("\(srs.count)", trs("在複習裡"))
            big("\(mature)", trs("記熟了"), T.oliveInk)
            big("\(due)", trs("要複習"), T.pinkInk)
        }
    }
}
