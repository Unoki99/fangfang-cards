import Foundation

// MARK: - 日語 助詞: what each does, examples (written for this app), and where they sit in a sentence (the map)
//
// In the examples, [ ] marks a particle and { } a grammatical suffix, so they get their colours.

struct JaParticle: Identifiable {
    var id: String { p + "|" + group }
    let p: String
    let group: String
    let zh: String
    let en: String
    /// (marked Japanese, English)
    let ex: [(String, String)]
}

enum JaParticles {
    /// the groups of the map, in sentence order
    static let groups: [(String, String)] = [
        ("主題・主語", "who / what the sentence is about"),
        ("時間・地點", "when / where / from / to"),
        ("對象", "the object, the person"),
        ("方法・一起", "how, with what, with whom"),
        ("連接・修飾", "joining nouns"),
        ("限定・強調", "only, also, even"),
        ("句末語氣", "at the end: question, feeling"),
    ]

    static let all: [JaParticle] = [
        JaParticle(p: "は", group: "主題・主語", zh: "主題：「說到…」。整句話在說它。唸 wa。", en: "topic marker: \"as for…\" (read wa)",
                   ex: [("私[は]学生{です}。", "I am a student."), ("今日[は]暑い{です}[ね]。", "It's hot today, isn't it.")]),
        JaParticle(p: "が", group: "主題・主語", zh: "主語：誰／什麼做了這件事，或新的訊息、喜歡／會的對象。", en: "subject marker; new information; the object of 好き・できる",
                   ex: [("猫[が]寝{て}{いる}。", "A cat is sleeping."), ("私[は]寿司[が]好き{です}。", "I like sushi.")]),
        JaParticle(p: "も", group: "限定・強調", zh: "「也、都」。代替は、が、を。", en: "\"also, too\" (takes the place of は・が・を)",
                   ex: [("私[も]行き{ます}。", "I'm going too."), ("肉[も]魚[も]食べ{ます}。", "I eat both meat and fish.")]),
        JaParticle(p: "を", group: "對象", zh: "受詞：動作的對象；也表示經過的地方。唸 o。", en: "direct object; the place passed through (read o)",
                   ex: [("水[を]飲み{ます}。", "I drink water."), ("公園[を]散歩する。", "I take a walk through the park.")]),
        JaParticle(p: "に", group: "時間・地點", zh: "時間點、存在的地方、去的目的地、給的對象。", en: "point in time, where something is, destination, to whom",
                   ex: [("七時[に]起き{ます}。", "I get up at seven."), ("友達[に]本[を]あげ{た}。", "I gave my friend a book.")]),
        JaParticle(p: "で", group: "時間・地點", zh: "動作發生的地方；也表示工具、方法、原因。", en: "where an action happens; by means of; because of",
                   ex: [("図書館[で]勉強する。", "I study at the library."), ("バス[で]行き{ます}。", "I go by bus.")]),
        JaParticle(p: "へ", group: "時間・地點", zh: "方向「往…」。唸 e。", en: "direction: \"towards\" (read e)",
                   ex: [("日本[へ]行き{たい}。", "I want to go to Japan.")]),
        JaParticle(p: "から", group: "時間・地點", zh: "起點「從…」；接在句子後面是「因為…」。", en: "\"from\"; after a clause: \"because\"",
                   ex: [("九時[から]働き{ます}。", "I work from nine."), ("雨{だ}[から]、行か{ない}。", "It's raining, so I won't go.")]),
        JaParticle(p: "まで", group: "時間・地點", zh: "終點「到…」。", en: "\"until, as far as\"",
                   ex: [("駅[まで]歩き{ます}。", "I walk to the station."), ("五時[まで]待っ{た}。", "I waited until five.")]),
        JaParticle(p: "と", group: "方法・一起", zh: "「和…（一起）」；完整列舉「A 和 B」；引用。", en: "\"with (someone)\"; \"A and B\" (all of them); quoting",
                   ex: [("母[と]話し{た}。", "I talked with my mother."), ("ペン[と]紙[が]要る。", "I need a pen and paper.")]),
        JaParticle(p: "や", group: "連接・修飾", zh: "不完整列舉「A 啦 B 啦（等等）」。", en: "\"A, B and so on\" (some of them)",
                   ex: [("りんご[や]バナナ[を]買っ{た}。", "I bought apples, bananas and such.")]),
        JaParticle(p: "の", group: "連接・修飾", zh: "「的」：連接兩個名詞。", en: "\"'s, of\": joins two nouns",
                   ex: [("私[の]本", "my book"), ("日本語[の]先生", "a Japanese teacher")]),
        JaParticle(p: "だけ", group: "限定・強調", zh: "「只有、只」（中性）。", en: "\"only, just\" (neutral)",
                   ex: [("水[だけ]飲ん{だ}。", "I only drank water.")]),
        JaParticle(p: "しか", group: "限定・強調", zh: "「只…（不夠）」，後面一定是否定。", en: "\"nothing but\" (always with a negative verb)",
                   ex: [("百円[しか]ない。", "I only have a hundred yen.")]),
        JaParticle(p: "か", group: "句末語氣", zh: "疑問「…嗎？」；在名詞中間是「或」。", en: "question marker; between nouns: \"or\"",
                   ex: [("これ[は]何{です}[か]。", "What is this?"), ("お茶[か]コーヒー", "tea or coffee")]),
        JaParticle(p: "ね", group: "句末語氣", zh: "「…吧、…呢」：希望對方同意。", en: "\"…isn't it?\": looking for agreement",
                   ex: [("いい天気{です}[ね]。", "Nice weather, isn't it.")]),
        JaParticle(p: "よ", group: "句末語氣", zh: "「…喔、…啦」：告訴對方他不知道的事。", en: "\"you know\": telling something new",
                   ex: [("この店[は]安い{です}[よ]。", "This shop is cheap, you know.")]),
    ]

    /// the sentence the map draws: each particle in its place
    static let mapSentence = "私[は]昨日友達[と]駅[から]学校[まで]バス[で]行っ{た}。"
    static let mapEnglish = "Yesterday I went from the station to school by bus with a friend."
}
