import SwiftUI

// A practice left half way (closed, or the app shut) carries on where it was the next time it's opened.
// Each kind of practice keeps one, for 台語 and 華語 apart, with the 練習範圍 it was started in.
// It's thrown away when the practice is finished, started again, or after two weeks.

enum PracticeSave {
    private static func key(_ name: String, _ zh: Bool) -> String { "practice.\(name).\(zh ? "zh" : "tw")" }

    private struct Box<T: Codable>: Codable { let t: Double; let scope: Int; let v: T }

    static func save<T: Codable>(_ v: T, _ name: String, zh: Bool, scope: Int) {
        guard let d = try? JSONEncoder().encode(Box(t: Date().timeIntervalSince1970, scope: scope, v: v)) else { return }
        UserDefaults.standard.set(d, forKey: key(name, zh))
    }

    static func load<T: Codable>(_ type: T.Type, _ name: String, zh: Bool, scope: Int) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key(name, zh)),
              let b = try? JSONDecoder().decode(Box<T>.self, from: d) else { return nil }
        guard b.scope == scope, Date().timeIntervalSince1970 - b.t < 14 * 86400 else { clear(name, zh: zh); return nil }
        return b.v
    }

    static func clear(_ name: String, zh: Bool) { UserDefaults.standard.removeObject(forKey: key(name, zh)) }
}

/// the toolbar button that throws the saved practice away and starts again
struct RestartPracticeButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "arrow.counterclockwise") }
            .accessibilityLabel(tr("重新開始"))
    }
}

/// "接著上次的練習" for a moment at the top, after a practice has been picked up again
struct ResumedNote: View {
    @Binding var shown: Bool
    var body: some View {
        if shown {
            Text(tr("接著上次的練習"))
                .ffFont(.footnote, .semibold).foregroundStyle(T.btnInk)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(T.btn))
                .overlay(Capsule().stroke(T.btnEdge, lineWidth: 1.5))
                .transition(.opacity.combined(with: .move(edge: .top)))
                .task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation(.snappy) { shown = false }
                }
        }
    }
}
