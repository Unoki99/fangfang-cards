import Foundation
import SwiftUI
import JavaScriptCore
import Compression

// MARK: - 詞典資料: installing the dictionaries in the app
//
// The dictionaries' licences don't allow sharing changed versions of them (教育部's CC BY-ND, 兩岸常用詞典's
// CC BY-NC-ND), so the app's data isn't on GitHub. Instead of building it on a Mac (install.sh), the app can fetch
// the original files from where their makers publish them and build its own copy, on the phone, with the same
// converters (Install/*.js, the same code tools/convert.js runs with node). The data built is kept in Application
// Support/Dictionaries; a file built into the app by install.sh is used when there's none there.

/// where the dictionaries' data files are
enum DataFiles {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var u = base.appendingPathComponent("Dictionaries", isDirectory: true)
        if !FileManager.default.fileExists(atPath: u.path) {
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            // (made again from the original files whenever needed: not in the iCloud backup)
            var v = URLResourceValues(); v.isExcludedFromBackup = true
            try? u.setResourceValues(v)
        }
        return u
    }
    /// the copy installed in the app (it may not be there)
    static func installed(_ name: String) -> URL { folder.appendingPathComponent(name + ".json") }
    /// the file to read: the one installed in the app, or the one built into it
    static func url(_ name: String) -> URL? {
        let u = installed(name)
        if FileManager.default.fileExists(atPath: u.path) { return u }
        return Bundle.main.url(forResource: name, withExtension: "json")
    }
    static func isInstalled(_ name: String) -> Bool { FileManager.default.fileExists(atPath: installed(name).path) }
    static func isBuiltIn(_ name: String) -> Bool { Bundle.main.url(forResource: name, withExtension: "json") != nil }
    static func has(_ name: String) -> Bool { isInstalled(name) || isBuiltIn(name) }
    /// the size of the installed copy
    static func size(_ name: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: installed(name).path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

// MARK: zip (.ods) and xz

enum Unpack {
    /// one file out of a zip file (an .ods is one)
    static func zipEntry(_ file: URL, _ name: String) throws -> Data {
        let d = try Data(contentsOf: file, options: .mappedIfSafe)
        return try d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws -> Data in
            let n = raw.count
            func u16(_ o: Int) -> Int { Int(raw[o]) | (Int(raw[o + 1]) << 8) }
            func u32(_ o: Int) -> Int { u16(o) | (u16(o + 2) << 16) }
            guard n >= 22 else { throw CocoaError(.fileReadCorruptFile) }
            var e = n - 22
            while e >= 0 && u32(e) != 0x06054b50 { e -= 1 }
            guard e >= 0 else { throw CocoaError(.fileReadCorruptFile) }
            let count = u16(e + 10)
            var p = u32(e + 16)
            for _ in 0..<count {
                guard p + 46 <= n else { break }
                let method = u16(p + 10), csize = u32(p + 20), usize = u32(p + 24)
                let nlen = u16(p + 28), xlen = u16(p + 30), clen = u16(p + 32)
                let local = u32(p + 42)
                let fname = String(decoding: UnsafeRawBufferPointer(rebasing: raw[(p + 46)..<(p + 46 + nlen)]), as: UTF8.self)
                if fname == name {
                    let lnlen = u16(local + 26), lxlen = u16(local + 28)
                    let start = local + 30 + lnlen + lxlen
                    guard start + csize <= n, let base = raw.baseAddress else { throw CocoaError(.fileReadCorruptFile) }
                    let src = base.advanced(by: start).assumingMemoryBound(to: UInt8.self)
                    if method == 0 { return Data(bytes: src, count: csize) }
                    guard usize > 0 else { return Data() }
                    var out = Data(count: usize)
                    let got = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
                        // (COMPRESSION_ZLIB is the raw deflate a zip file uses)
                        compression_decode_buffer(dst.baseAddress!.assumingMemoryBound(to: UInt8.self), usize,
                                                  src, csize, nil, COMPRESSION_ZLIB)
                    }
                    guard got == usize else { throw CocoaError(.fileReadCorruptFile) }
                    return out
                }
                p += 46 + nlen + xlen + clen
            }
            throw CocoaError(.fileNoSuchFile)
        }
    }

    /// an .xz file's contents
    static func xz(_ file: URL) throws -> Data {
        try stream(try Data(contentsOf: file, options: .mappedIfSafe), skip: 0, COMPRESSION_LZMA)
    }

    /// a .gz file's contents (the header skipped, then the raw deflate COMPRESSION_ZLIB reads)
    static func gzip(_ file: URL) throws -> Data {
        let d = try Data(contentsOf: file, options: .mappedIfSafe)
        let b = [UInt8](d.prefix(10))
        guard b.count == 10, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { throw CocoaError(.fileReadCorruptFile) }
        let flags = b[3]
        var p = 10
        if flags & 4 != 0, d.count > p + 2 { p += 2 + (Int(d[d.startIndex + p]) | (Int(d[d.startIndex + p + 1]) << 8)) }
        if flags & 8 != 0 { while p < d.count && d[d.startIndex + p] != 0 { p += 1 }; p += 1 }      // file name
        if flags & 16 != 0 { while p < d.count && d[d.startIndex + p] != 0 { p += 1 }; p += 1 }     // comment
        if flags & 2 != 0 { p += 2 }
        return try stream(d, skip: p, COMPRESSION_ZLIB)
    }

    private static func stream(_ src: Data, skip: Int, _ algorithm: compression_algorithm) throws -> Data {
        var out = Data()
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, algorithm) == COMPRESSION_STATUS_OK else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { compression_stream_destroy(stream) }
        let size = 1 << 20
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buf.deallocate() }
        try src.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws in
            guard let base = raw.baseAddress, raw.count > skip else { return }
            stream.pointee.src_ptr = base.advanced(by: skip).assumingMemoryBound(to: UInt8.self)
            stream.pointee.src_size = raw.count - skip
            while true {
                stream.pointee.dst_ptr = buf
                stream.pointee.dst_size = size
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let made = size - stream.pointee.dst_size
                if made > 0 { out.append(buf, count: made) }
                if status == COMPRESSION_STATUS_END { break }
                if status != COMPRESSION_STATUS_OK { throw CocoaError(.fileReadCorruptFile) }
            }
        }
        return out
    }
}

// MARK: the dictionaries that can be installed

/// one dictionary: where its original files are, and the converter that makes the app's file from them
struct DictPack: Identifiable {
    struct Source {
        let file: String
        let url: String
        /// (the dictionary is still made without it, only a little less complete)
        var optional = false
        /// the converter's name for it (nil: from the file's name)
        var arg: String? = nil
        /// not downloaded when this other file was (a second place to get the same file from)
        var unless: String? = nil
    }
    let id: String
    /// the language (0 台語, 1 華語, 2 粵語, 3 客語)
    let lang: Int
    let name: String
    /// the app's files it makes ("hak" → hak.json)
    let outputs: [String]
    let sources: [Source]
    /// Install/<script>.js and the function in it, called with {src: the folder of the sources, out: the folder
    /// to write to, and each source by its file name}
    let script: String
    let function: String
    /// where the data is from (shown before installing)
    let from: String
    /// about how big the downloads are
    let download: String
    /// files inside the app the converter reads too (argument → file name in the app)
    var bundled: [String: String] = [:]

    static let essay = Source(file: "essay.txt", url: "https://raw.githubusercontent.com/rime/rime-essay/master/essay.txt", optional: true)
    static let cedict = Source(file: "cedict_ts.u8", url: "https://raw.githubusercontent.com/cschiller/zhongwen/main/data/cedict_ts.u8", optional: true)

    static let hakka: DictPack = {
        let base = "https://hakkadict.moe.edu.tw/static/resource/客語資源下載/本辭典的文字/"
        let files = Lang.hakAccents.map { DictPack.Source(file: $0 + "腔詞條詞目文字.ods", url: base + $0 + "腔詞條詞目文字.ods", optional: $0 != "四縣") }
        return DictPack(id: "hak", lang: 3, name: "客語", outputs: ["hak"], sources: files + [essay, cedict],
                        script: "hakka", function: "buildHakka",
                        from: "教育部《臺灣客語辭典》（六個腔，CC BY-ND 3.0 臺灣）、rime-essay 詞頻、CC-CEDICT 英文解釋",
                        download: "約 20 MB")
    }()

    static let taigi = DictPack(
        id: "tw", lang: 0, name: "台語", outputs: ["dict", "cards"],
        sources: [Source(file: "kautian.ods", url: "https://sutian.moe.edu.tw/media/senn/ods/kautian.ods"),
                  Source(file: "essay.txt", url: "https://raw.githubusercontent.com/rime/rime-essay/master/essay.txt")],
        script: "taigi", function: "buildTaigi",
        from: "教育部《臺灣台語常用詞辭典》（CC BY-ND 3.0 臺灣）、rime-essay 字頻",
        download: "約 15 MB", bundled: ["own": "twown.json"])

    static let mandarin: DictPack = {
        let g = "https://raw.githubusercontent.com/"
        return DictPack(
            id: "zh", lang: 1, name: "華語", outputs: ["zh", "inputcodes"],
            sources: [Source(file: "dict-csld.json", url: g + "g0v/moedict-data-csld/master/dict-csld.json", arg: "csld"),
                      Source(file: "essay.txt", url: g + "rime/rime-essay/master/essay.txt"),
                      cedict,
                      Source(file: "hsk30.csv", url: g + "ivankra/hsk30/master/hsk30-expanded.csv", optional: true, arg: "hsk"),
                      Source(file: "tocfl.csv", url: g + "ivankra/tocfl/master/expanded/tocfl.csv", optional: true, arg: "tocfl"),
                      Source(file: "dict-revised.json.xz", url: g + "g0v/moedict-data/master/dict-revised.json.xz", optional: true, arg: "moe"),
                      Source(file: "hsk30-chars.csv", url: g + "ivankra/hsk30/master/hsk30-chars.csv", optional: true, arg: "hskChars"),
                      Source(file: "tbcl-chars.csv", url: g + "ivankra/tocfl/master/tbcl-chars.csv", optional: true, arg: "tbclChars"),
                      Source(file: "ids.txt", url: g + "cjkvi/cjkvi-ids/master/ids.txt", optional: true, arg: "ids"),
                      Source(file: "cj.yaml", url: g + "rime/rime-cangjie/master/cangjie5.base.dict.yaml", optional: true, arg: "cjBase"),
                      Source(file: "cjx.yaml", url: g + "rime/rime-cangjie/master/cangjie5.extended.dict.yaml", optional: true, arg: "cjExt"),
                      Source(file: "wb.yaml", url: g + "rime/rime-wubi/master/wubi86.dict.yaml", optional: true, arg: "wubi")],
            script: "mandarin", function: "buildMandarinAll",
            from: "中華文化總會《兩岸常用詞典》（CC BY-NC-ND，g0v 萌典整理）、教育部《重編國語辭典修訂本》、CC-CEDICT、HSK 3.0 和 TOCFL 詞表、倉頡和五筆碼表（Rime）",
            download: "約 60 MB")
    }()

    /// 說文解字 (段玉裁注): for every language's single characters
    static let shuowen = DictPack(
        id: "sw", lang: -1, name: "說文解字", outputs: ["shuowen"],
        sources: [Source(file: "swjz.xml", url: "https://raw.githubusercontent.com/cjkvi/cjkvi-dict/master/swjz.xml", arg: "src")],
        script: "shuowen", function: "buildShuowen",
        from: "段玉裁《說文解字注》（cjkvi-dict，GPLv2）：單字詞條下面顯示說文的解釋、段注和六書",
        download: "約 6 MB")

    /// 日語: JMdict (English) and KANJIDIC2, from the EDRDG (CC BY-SA 4.0)
    static let japanese = DictPack(
        id: "ja", lang: 4, name: "日語", outputs: ["ja"],
        sources: [Source(file: "JMdict_e_examp.gz", url: "http://ftp.edrdg.org/pub/Nihongo/JMdict_e_examp.gz", arg: "jmdict"),
                  Source(file: "kanjidic2.xml.gz", url: "http://ftp.edrdg.org/pub/Nihongo/kanjidic2.xml.gz", optional: true, arg: "kanjidic")],
        script: "japanese", function: "buildJapanese",
        from: "JMdict 與 KANJIDIC2（Electronic Dictionary Research and Development Group，CC BY-SA 4.0），例句來自 Tatoeba（CC BY 2.0 FR）",
        download: "約 25 MB")

    /// 粵語: CC-CEDICT, CC-Canto (CC BY-SA), rime-cantonese (CC BY 4.0 / ODbL), 開放粵語字典 (CC BY 3.0). Without
    /// Wiktionary (2.5 GB): the Mac's install.sh version also has its meanings, example sentences and recordings.
    static let cantonese: DictPack = {
        let g = "https://raw.githubusercontent.com/"
        let jd = g + "aaronhktan/jyut-dict/main/src/dictionaries/cedict/data/"
        let rc = g + "rime/rime-cantonese/main/"
        return DictPack(
            id: "yue", lang: 2, name: "粵語", outputs: ["yue"],
            sources: [Source(file: cedict.file, url: cedict.url, arg: "cedict"),
                      Source(file: "CC-CANTO.txt", url: jd + "CC-CANTO.txt", arg: "canto"),
                      Source(file: "READINGS.txt", url: jd + "READINGS.txt", arg: "readings"),
                      Source(file: "jyut6ping3.words.dict.yaml", url: rc + "jyut6ping3.words.dict.yaml", arg: "words"),
                      Source(file: "jyut6ping3.chars.dict.yaml", url: rc + "jyut6ping3.chars.dict.yaml", arg: "chars"),
                      Source(file: "essay-cantonese.txt", url: rc + "essay-cantonese.txt", arg: "essay"),
                      Source(file: "yyzd.txt", url: g + "kfcd/yyzd/master/dist/tsv/%E7%B9%81%E9%AB%94/%E7%B2%B5%E8%AA%9E%E5%AD%97%E5%85%B8_%28%E7%B2%B5%E6%8B%BC%29.txt", arg: "yyzd")],
            script: "cantonese", function: "buildCantonese",
            from: "CC-CEDICT、CC-Canto（CC BY-SA）、rime-cantonese（CC BY 4.0）、開放粵語字典（CC BY 3.0）",
            download: "約 25 MB")
    }()

    /// 瑞典語: Folkets lexikon (KTH, CC BY-SA 2.5; from GitHub, or from KTH when GitHub doesn't have it), the
    /// FrequencyWords list (CC BY-SA 4.0) for the common words, and the Chinese meanings from the Chinese Wiktionary
    /// (kaikki.org, CC BY-SA)
    static let swedish = DictPack(
        id: "sv", lang: 5, name: "瑞典語", outputs: ["sv"],
        sources: [Source(file: "folkets.xml", url: "https://raw.githubusercontent.com/antonlisq/convert-dict/main/folkets_sv_en_public.xml", optional: true, arg: "folkets2"),
                  Source(file: "folkets_kth.xml", url: "http://folkets-lexikon.csc.kth.se/folkets/folkets_sv_en_public.xml", optional: true, arg: "folkets", unless: "folkets.xml"),
                  Source(file: "sv_50k.txt", url: "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/sv/sv_50k.txt", optional: true, arg: "freq"),
                  Source(file: cedict.file, url: cedict.url, optional: true, arg: "cedict"),
                  Source(file: essay.file, url: essay.url, optional: true, arg: "essay"),
                  Source(file: "zhwikt-sv.jsonl", url: "https://kaikki.org/zhwiktionary/%E7%91%9E%E5%85%B8%E8%AA%9E/kaikki.org-dictionary-%E7%91%9E%E5%85%B8%E8%AA%9E.jsonl", optional: true, arg: "zhwikt")],
        script: "swedish", function: "buildSwedish",
        from: "Folkets lexikon（KTH，CC BY-SA 2.5）、FrequencyWords 詞頻（CC BY-SA 4.0）、維基詞典的中文解釋（kaikki.org，CC BY-SA）、CC-CEDICT（由英文推測的中文解釋，CC BY-SA）；詞素依規則推算",
        download: "約 95 MB（中文解釋佔大部分）")

    /// every dictionary the app can install
    static let all: [DictPack] = [taigi, mandarin, cantonese, hakka, japanese, swedish, shuowen]
    static func of(lang: Int) -> DictPack? { all.first { $0.lang == lang } }
}

// MARK: installing

@MainActor
final class DictInstaller: ObservableObject {
    static let shared = DictInstaller()

    enum State: Equatable {
        case idle
        case working(Double, String)
        case failed(String)
    }
    @Published private(set) var states: [String: State] = [:]
    /// (redrawn after installing or removing)
    @Published private(set) var version = 0

    func state(_ p: DictPack) -> State { states[p.id] ?? .idle }
    var busy: Bool { states.values.contains { if case .working = $0 { return true }; return false } }

    func remove(_ p: DictPack) {
        for o in p.outputs { try? FileManager.default.removeItem(at: DataFiles.installed(o)) }
        states[p.id] = .idle
        version += 1
        Shuowen.reset(); Store.shared.dictionaryChanged(p.lang)
    }

    func install(_ p: DictPack) {
        if case .working = state(p) { return }
        states[p.id] = .working(0, trs("下載中…"))
        Task {
            do {
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("install-" + p.id, isDirectory: true)
                try? FileManager.default.removeItem(at: work)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: work) }
                // 1. the original files
                var have: [String: String] = [:]
                for (i, s) in p.sources.enumerated() {
                    if let u = s.unless, have[u] != nil { continue }
                    states[p.id] = .working(0.3 * Double(i) / Double(max(p.sources.count, 1)), tr("下載 \(s.file)…"))
                    do {
                        let dest = work.appendingPathComponent(s.file)
                        try await Self.download(s.url, to: dest)
                        have[s.file] = dest.path
                    } catch {
                        if !s.optional { throw InstallError.download(s.file, error.localizedDescription) }
                    }
                }
                // 2. the app's files, made from them (on another thread: it takes a while)
                states[p.id] = .working(0.3, trs("整理資料…"))
                let out = work.appendingPathComponent("out", isDirectory: true)
                try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                var args: [String: Any] = ["src": work.path, "outDir": out.path]
                for o in p.outputs { args["out_" + o] = out.appendingPathComponent(o + ".json").path }
                if let first = p.outputs.first { args["out"] = out.appendingPathComponent(first + ".json").path }
                for s in p.sources { args[s.arg ?? Self.argName(s.file)] = have[s.file] ?? NSNull() }
                for (arg, file) in p.bundled {
                    let name = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
                    let u = Bundle.main.url(forResource: name, withExtension: ext)
                        ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Install")
                    args[arg] = u?.path ?? NSNull()
                }
                let id = p.id
                try await JSRunner.run(script: p.script, function: p.function, args: args) { f, text in
                    Task { @MainActor in
                        DictInstaller.shared.states[id] = .working(0.3 + 0.7 * min(max(f, 0), 1), text)
                    }
                }
                // 3. in place (only now: a half-made file is never read)
                for o in p.outputs {
                    let made = out.appendingPathComponent(o + ".json")
                    guard FileManager.default.fileExists(atPath: made.path) else {
                        // (the first file is the dictionary; the others, like 華語's 倉頡／五筆 codes, can be missing)
                        if o == p.outputs.first { throw InstallError.notMade(o) } else { continue }
                    }
                    let dest = DataFiles.installed(o)
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: made, to: dest)
                }
                states[p.id] = .idle
                version += 1
                Shuowen.reset(); Store.shared.dictionaryChanged(p.lang)
            } catch {
                states[p.id] = .failed((error as? InstallError)?.text ?? error.localizedDescription)
            }
        }
    }

    /// "cedict_ts.u8" → "cedict", "essay.txt" → "essay" (a converter's argument); an accent's file keeps its name
    nonisolated static func argName(_ file: String) -> String {
        if file == "cedict_ts.u8" { return "cedict" }
        if file == "essay.txt" { return "essay" }
        if file == "kautian.ods" { return "ods" }
        return "file:" + file
    }

    enum InstallError: Error {
        case download(String, String)
        case notMade(String)
        case script(String)
        var text: String {
            switch self {
            case .download(let f, let why): return tr("下載不到 \(f)：\(why)")
            case .notMade(let o): return tr("沒有做出 \(o).json。")
            case .script(let s): return tr("整理資料的時候出錯：\(s)")
            }
        }
    }

    nonisolated static func download(_ s: String, to dest: URL) async throws {
        guard let url = URL(string: s) ?? s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap({ URL(string: $0) }) else {
            throw URLError(.badURL)
        }
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            throw URLError(.badServerResponse)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        // a link on GitHub (expanded/tocfl.csv → tocfl-202307.csv) comes as the name of the file it points to
        if let size = (try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? NSNumber, size.intValue < 300,
           let text = try? String(contentsOf: dest, encoding: .utf8) {
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.range(of: #"^[A-Za-z0-9_./-]+\.(csv|txt|json)$"#, options: .regularExpression) != nil,
               let next = URL(string: name, relativeTo: url)?.absoluteURL, next != url {
                try await download(next.absoluteString, to: dest)
            }
        }
    }
}

// MARK: the converters (JavaScriptCore)

enum JSRunner {
    /// runs Install/<script>.js's function with args, on a thread of its own (a big stack: the converters' regular
    /// expressions go deep); progress: (0…1, what it's doing)
    static func run(script: String, function: String, args: [String: Any],
                    progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let box = ArgsBox(args)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let t = Thread {
                do { try runNow(script: script, function: function, args: box.args, progress: progress); cont.resume() }
                catch { cont.resume(throwing: error) }
            }
            t.stackSize = 16 << 20
            t.qualityOfService = .userInitiated
            t.start()
        }
    }

    private final class ArgsBox: @unchecked Sendable {
        let args: [String: Any]
        init(_ a: [String: Any]) { args = a }
    }

    private static func source(_ name: String) -> String? {
        let u = Bundle.main.url(forResource: name, withExtension: "js")
            ?? Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "Install")
        return u.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    private static func runNow(script: String, function: String, args: [String: Any],
                               progress: @escaping @Sendable (Double, String) -> Void) throws {
        guard let ctx = JSContext() else { throw DictInstaller.InstallError.script("JavaScript") }
        var failure: String?
        ctx.exceptionHandler = { _, e in failure = failure ?? (e?.toString() ?? "?") }
        let host = JSValue(newObjectIn: ctx)!
        func fail(_ msg: String) {
            if let c = JSContext.current() { c.exception = JSValue(newErrorFromMessage: msg, in: c) }
        }
        let readText: @convention(block) (String) -> String? = { p in
            if let s = try? String(contentsOfFile: p, encoding: .utf8) { return s }
            fail("讀不到 " + p); return nil
        }
        let unzipText: @convention(block) (String, String) -> String? = { p, name in
            do { return String(decoding: try Unpack.zipEntry(URL(fileURLWithPath: p), name), as: UTF8.self) }
            catch { fail("解不開 " + p); return nil }
        }
        let xzText: @convention(block) (String) -> String? = { p in
            do { return String(decoding: try Unpack.xz(URL(fileURLWithPath: p)), as: UTF8.self) }
            catch { fail("解不開 " + p); return nil }
        }
        let gunzipText: @convention(block) (String) -> String? = { p in
            do { return String(decoding: try Unpack.gzip(URL(fileURLWithPath: p)), as: UTF8.self) }
            catch { fail("解不開 " + p); return nil }
        }
        let writeText: @convention(block) (String, String) -> Bool = { p, text in
            do { try text.write(toFile: p, atomically: true, encoding: .utf8); return true }
            catch { fail("寫不進 " + p); return false }
        }
        let list: @convention(block) (String) -> [String] = { d in (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [] }
        let exists: @convention(block) (String) -> Bool = { p in FileManager.default.fileExists(atPath: p) }
        let log: @convention(block) (String) -> Void = { t in print("[install] " + t) }
        let prog: @convention(block) (Double, String) -> Void = { f, t in progress(f, t) }
        host.setObject(readText, forKeyedSubscript: "readText" as NSString)
        host.setObject(unzipText, forKeyedSubscript: "unzipText" as NSString)
        host.setObject(xzText, forKeyedSubscript: "xzText" as NSString)
        host.setObject(gunzipText, forKeyedSubscript: "gunzipText" as NSString)
        host.setObject(writeText, forKeyedSubscript: "writeText" as NSString)
        host.setObject(list, forKeyedSubscript: "list" as NSString)
        host.setObject(exists, forKeyedSubscript: "exists" as NSString)
        host.setObject(log, forKeyedSubscript: "log" as NSString)
        host.setObject(prog, forKeyedSubscript: "progress" as NSString)
        ctx.setObject(host, forKeyedSubscript: "host" as NSString)
        // (reading a file line by line: one call for the whole file, split here)
        ctx.evaluateScript("""
            host.readLines = function (p, fn) {
                const t = host.readText(p); if (t === null || t === undefined) return;
                const ls = t.split("\\n"); for (let i = 0; i < ls.length; i++) fn(ls[i].endsWith("\\r") ? ls[i].slice(0, -1) : ls[i]);
            };
            """)
        for name in ["common", script] {
            guard let code = source(name) else { throw DictInstaller.InstallError.script(name + ".js") }
            ctx.evaluateScript(code, withSourceURL: URL(string: "file:///" + name + ".js"))
            if let f = failure { throw DictInstaller.InstallError.script(f) }
        }
        // the arguments as JSON (a converter takes {src, out, essay, cedict, …})
        var a: [String: Any] = [:]
        for (k, v) in args {
            if k.hasPrefix("file:") { continue }
            a[k] = v
        }
        let data = try JSONSerialization.data(withJSONObject: a)
        let json = String(decoding: data, as: UTF8.self)
        ctx.setObject(json, forKeyedSubscript: "__args" as NSString)
        ctx.evaluateScript("\(function)(JSON.parse(__args))")
        if let f = failure { throw DictInstaller.InstallError.script(f) }
    }
}

// MARK: 設定 → 詞典資料

struct DictDataSettings: View {
    @ObservedObject private var installer = DictInstaller.shared
    @EnvironmentObject var store: Store
    @State private var confirmRemove: DictPack?

    var body: some View {
        SettingsPage(title: tr("詞典資料")) {
            Section {
                ForEach(DictPack.all) { p in row(p) }
            } footer: {
                Text(tr("詞典的授權不允許分享改過的版本，所以 App 從原本發布的地方下載檔案，在這台裝置上自己整理（要網路，大概一兩分鐘）。不熟、熟悉和收藏的詞不會因為移除詞典而不見。"))
            }
            Section {
            } footer: {
                Text(tr("詞典不是內建的：第一次選語言的時候會自動下載安裝，之後在這裡安裝其他語言的。維基詞典的檔案太大（2.5 GB），不在手機上整理：華語的四川話讀音和台語詞的英文（英文查詞要用）是 install.sh 在 Mac 上做好放進 App 的；粵語的例句和錄音只有 Mac 上建立的資料裡有。"))
            }
        }
        .confirmationDialog(tr("移除這個詞典？"), isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), titleVisibility: .visible) {
            if let p = confirmRemove {
                Button(tr("移除\(trs(p.name))詞典"), role: .destructive) { installer.remove(p); confirmRemove = nil }
            }
        } message: {
            Text(tr("要用的時候可以再安裝。"))
        }
    }

    @ViewBuilder private func row(_ p: DictPack) -> some View {
        let _ = installer.version
        let installed = p.outputs.prefix(1).allSatisfy { DataFiles.isInstalled($0) }
        let builtIn = p.outputs.prefix(1).allSatisfy { DataFiles.isBuiltIn($0) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(trs(p.name)).ffFont(.headline).foregroundStyle(T.langColors(p.lang).ink)
                Spacer()
                if installed {
                    Text(tr("已安裝・\(ByteCountFormatter.string(fromByteCount: p.outputs.reduce(0) { $0 + DataFiles.size($1) }, countStyle: .file))"))
                        .ffFont(.footnote).foregroundStyle(T.greenInk)
                } else if builtIn {
                    Text(tr("App 內建")).ffFont(.footnote).foregroundStyle(T.muted)
                } else {
                    Text(tr("還沒安裝")).ffFont(.footnote).foregroundStyle(T.muted)
                }
            }
            Text(p.from).ffFont(.caption).foregroundStyle(T.muted)
            switch installer.state(p) {
            case .working(let f, let what):
                ProgressView(value: f) { Text(what).ffFont(.caption).foregroundStyle(T.muted) }
            case .failed(let why):
                Text(why).ffFont(.caption).foregroundStyle(T.rustInk)
                buttons(p, installed: installed)
            case .idle:
                buttons(p, installed: installed)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func buttons(_ p: DictPack, installed: Bool) -> some View {
        HStack(spacing: 10) {
            Button(installed ? trs("重新安裝") : tr("安裝（下載\(p.download)）")) { installer.install(p) }
                .buttonStyle(.bordered)
                .disabled(installer.busy)
            if installed {
                Button(tr("移除"), role: .destructive) { confirmRemove = p }
                    .buttonStyle(.bordered)
                    .disabled(installer.busy)
            }
        }
    }
}


/// a language whose dictionary isn't there yet (台語 without cards.json): what to do, and the button to install it
struct MissingDictView: View {
    let lang: Int
    @ObservedObject private var installer = DictInstaller.shared
    var body: some View {
        VStack(spacing: 16) {
            Text(tr("還沒有\(trs(Lang.names[lang]))詞典")).ffFont(.title2, .bold).foregroundStyle(T.glyph)
            if let p = DictPack.of(lang: lang) {
                Text(p.from).ffFont(.footnote).foregroundStyle(T.muted).multilineTextAlignment(.center)
                switch installer.state(p) {
                case .working(let f, let what):
                    ProgressView(value: f) { Text(what).ffFont(.caption).foregroundStyle(T.muted) }
                        .frame(maxWidth: 320)
                case .failed(let why):
                    Text(why).ffFont(.footnote).foregroundStyle(T.rustInk).multilineTextAlignment(.center)
                    Button(tr("再試一次")) { installer.install(p) }.prominentButton(T.langColors(lang).edge)
                case .idle:
                    Button(tr("安裝（下載\(p.download)）")) { installer.install(p) }.prominentButton(T.langColors(lang).edge)
                }
                Text(tr("App 會從原本發布的地方下載詞典，在這台裝置上整理，大概一兩分鐘。也可以到「設定 → 語言與讀音」先換別的語言。"))
                    .ffFont(.caption).foregroundStyle(T.muted).multilineTextAlignment(.center)
            } else {
                Text(tr("在 Mac 上用 install.sh 建立詞典資料。")).ffFont(.footnote).foregroundStyle(T.muted)
            }
        }
        .padding(28)
        .frame(maxWidth: 480)
        .background(RoundedRectangle(cornerRadius: 22).fill(T.fn.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(T.fnEdge, lineWidth: 1.5))
        .padding(20)
    }
}
