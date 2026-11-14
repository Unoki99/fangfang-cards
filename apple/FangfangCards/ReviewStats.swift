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
