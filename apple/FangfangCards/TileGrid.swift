import SwiftUI

/// the dictionary page's tiles, two to a row in the order given; an odd one out at the end takes the whole row
/// (no empty places). The same order in every language: 部首查字, 依詞類列出, 單詞比較, the language's own
/// (國語用詞, 日語借詞, 助詞…), 依常用度列出.
struct TileGrid: View {
    let tiles: [AnyView]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { i in
                HStack(spacing: 10) {
                    tiles[i]
                    if i + 1 < tiles.count { tiles[i + 1] }
                }
            }
        }
    }
}
