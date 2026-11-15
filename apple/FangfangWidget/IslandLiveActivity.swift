import WidgetKit
import SwiftUI
import AppIntents
import ActivityKit

// 動態島 (iPhone): one of your 不熟 words while you're away from the app. Small: the word on the left, its reading
// on the right (its meaning when held open). Pressed and held: the word bigger, 下一個, and a button for each language
// chosen in the app's 設定 → 詞典資料 → 動態島, opening that language's dictionary. In the app's theme colours.

struct IslandLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IslandAttributes.self) { ctx in
            // the lock screen (and where there's no Dynamic Island)
            IslandLockView(s: ctx.state)
                .activityBackgroundTint(IslandTheme(ctx.state).bg)
                .activitySystemActionForegroundColor(IslandTheme(ctx.state).text)
        } dynamicIsland: { ctx in
            let s = ctx.state, th = IslandTheme(s)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandText.colored(s.word, ink: th.text, size: 30, weight: .semibold)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        IslandText.colored(s.reading, ink: th.accent, size: 14, weight: .medium).lineLimit(1).minimumScaleFactor(0.6)
                        Text(s.meaning).font(.system(size: 12)).foregroundStyle(th.muted).lineLimit(2).multilineTextAlignment(.trailing)
                    }
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Button(intent: NextIslandWordIntent()) {
                                Label("下一個", systemImage: "arrow.right").font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(th.text)
                            .background(Capsule().fill(th.panel))
                            .overlay(Capsule().stroke(th.edge, lineWidth: 1))
                        }
                        // a button for each language: its dictionary in the app
                        if !s.langs.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(s.langs, id: \.self) { l in
                                    Link(destination: URL(string: "fangfangcards://dict?lang=\(l)")!) {
                                        Text(IslandLang.name(l)).font(.system(size: 13, weight: .semibold))
                                            .lineLimit(1).minimumScaleFactor(0.7)
                                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                                            .foregroundStyle(IslandLang.ink(l))
                                            .background(Capsule().fill(IslandLang.fill(l)))
                                            .overlay(Capsule().stroke(IslandLang.edge(l), lineWidth: 1))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            } compactLeading: {
                IslandText.colored(s.word, ink: th.text, size: 15, weight: .semibold)
                    .lineLimit(1).minimumScaleFactor(0.5)
            } compactTrailing: {
                // (only the reading: the meaning shows when the island is held open)
                IslandText.colored(s.reading, ink: th.accent, size: 12, weight: .medium)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: 92, alignment: .leading)
            } minimal: {
                IslandText.colored(Array(s.word.prefix(1)).map { WSeg(t: String($0.t.prefix(1)), c: $0.c) }, ink: th.text, size: 13, weight: .semibold)
            }
            .widgetURL(IslandLink.word(s))
            .keylineTint(th.accent)
        }
    }
}

/// the lock screen's: the word, its reading and meaning, the buttons
private struct IslandLockView: View {
    let s: IslandAttributes.ContentState
    var body: some View {
        let th = IslandTheme(s)
        HStack(spacing: 14) {
            IslandText.colored(s.word, ink: th.text, size: 32, weight: .semibold).lineLimit(1).minimumScaleFactor(0.5)
            VStack(alignment: .leading, spacing: 3) {
                IslandText.colored(s.reading, ink: th.accent, size: 15, weight: .medium).lineLimit(1).minimumScaleFactor(0.6)
                Text(s.meaning).font(.system(size: 13)).foregroundStyle(th.muted).lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                Button(intent: NextIslandWordIntent()) { Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold)).frame(width: 34, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(th.text).background(Capsule().fill(th.panel))
            }
        }
        .padding(14)
        .widgetURL(IslandLink.word(s))
    }
}

/// the app's theme as the app sent it
private struct IslandTheme {
    let bg, panel, edge, text, muted, accent: Color
    init(_ s: IslandAttributes.ContentState) {
        let c = s.colors.map(WT.color)
        func at(_ i: Int, _ d: Color) -> Color { i < c.count ? c[i] : d }
        bg = at(0, WT.bg); panel = at(1, WT.fn); edge = at(2, WT.fnEdge)
        text = at(3, WT.glyph); muted = at(4, WT.muted); accent = at(5, WT.blueInk)
    }
}

/// each language's name and colours (as in the app)
private enum IslandLang {
    static let names = ["台語", "華語", "粵語", "客語", "日語", "瑞典語"]
    static func name(_ l: Int) -> String { l >= 0 && l < names.count ? names[l] : "" }
    private static let fills: [UInt32] = [0x1d4630, 0x1f3d6b, 0x5a4a14, 0x5a1e2a, 0x5a2346, 0x0f4a4a]
    private static let edges: [UInt32] = [0x3fae66, 0x4f7dff, 0xc9a227, 0xd8434f, 0xff8cc6, 0x3fc9bd]
    private static let inks: [UInt32] = [0xb6f0c8, 0x9ad0ff, 0xffe58a, 0xffb3b8, 0xffc9e4, 0x9cf0e6]
    private static func c(_ a: [UInt32], _ l: Int) -> Color { WT.color(String(format: "%06x", a[min(max(l, 0), a.count - 1)])) }
    static func fill(_ l: Int) -> Color { c(fills, l) }
    static func edge(_ l: Int) -> Color { c(edges, l) }
    static func ink(_ l: Int) -> Color { c(inks, l) }
}

/// text in its tone colours (pieces without a colour in `ink`)
private enum IslandText {
    static func colored(_ segs: [WSeg], ink: Color, size: CGFloat, weight: Font.Weight) -> Text {
        segs.reduce(Text("")) { acc, sg in
            acc + Text(sg.t).foregroundColor(sg.c.map(WT.color) ?? ink)
        }
        .font(.system(size: size, weight: weight))
    }
}

/// the island tapped (not one of its buttons): the app, with the word shown in its dictionary
enum IslandLink {
    static func word(_ s: IslandAttributes.ContentState) -> URL? {
        var c = URLComponents()
        c.scheme = "fangfangcards"; c.host = "dict"
        c.queryItems = [URLQueryItem(name: "lang", value: String(s.kind)), URLQueryItem(name: "word", value: s.key)]
        return c.url
    }
}
