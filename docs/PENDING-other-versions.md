# Changes waiting for the other versions

Rounds that were done on one platform first. Each item: what changed, where it was done, and what the other
versions still need. When an item has been done everywhere, delete it here.

## Round of 2026-11-27 (iPhone / iPad only)

Done on iOS this round — still to do on **Android, Windows / Mac (desktop), the Firefox add-on**:

| Item | iOS | Android | Desktop | Add-on |
|---|---|---|---|---|
| 聲調顏色: 客語 only on / off (七聲 / 五聲 stays 台語's) | done | todo | todo | — |
| 新詞 swipe: ⇧ opens / closes 詳細, ⌫ undoes the last card | done | — | todo | — |
| TOCFL English level names: TOCFL 1–7 (the 7 levels) | done | todo | todo | — |
| Radios grouped by language again (not by stream kind) | done | todo | todo | — |
| Build scripts keep the downloaded dictionary files (Mac: ~/Library/Caches/FangfangCards/sources) and don't download them again; FANGFANG_REFRESH=1 to download again. Also the 四川話 data was rebuilt every run (version check 5, file says 4) | done (apple/build-data.sh, apple/install.sh) | todo (android-install.bat) | todo (install.ps1) | — |
| Practice of single characters: the most common first | done | todo | todo | — |
| 華語 pinyin search: lü / ǜ read as v (lv finds 綠; lu still finds lü words after the lu ones) | done | todo | todo | todo |
| 認識的漢字: a character marked 不熟 in another language no longer stays orange (長) | done | todo | todo | — |
| Swipe falls apart upside down (bitmap rows read the wrong way) | done | — | — | — |
| 方音 light tone keeps the syllable's own tone mark (˙ㄐㄧㆵ̇˙ㄍㄨㄚˋ) | done | todo | todo | todo |
| 客語 方音符號: ii ㄭ, m ㆬ, ng ㆭ, 入聲 ㆴㆵㆻ (陰入) / ㆴ̇ㆵ̇ㆻ̇ (陽入) | done (at display; the install table hz still has the old ones) | todo | todo | todo |
| 台語 own words (自訂) follow the 各地 reading rules (composed from each 字) | done | todo | todo | — |
| 台語 entry: 華 column says 臺華共同詞 (same in 華語) | done | todo | todo | — |
| Every dictionary: the 資料 (sources) line at the very bottom of the entry | done | todo | todo | — |
| 各地講法 page: each word its own row (no more opening every word above) | done | todo | todo | — |
| 詞典: the old 各地讀音 and 分類 tabs taken out | done | todo | todo | — |
| 華語 近／反: a word written the same with two readings keeps each 近／反 word for one reading (睡覺) | done | todo | todo | — |
| 瑞典語: the Chinese meanings beside the English (two columns) | done | todo | todo | — |
| 練習範圍: 收藏的詞 as a range | done | todo | todo | — |
| 練習範圍: 匯出這個範圍（CSV） | done | todo | todo | — |
| 電台與音樂: YouTube / Apple Music on top, radios by language, 歌詞 button at the bottom; 歌詞 out of 轉換 | done | todo (layout already like this) | already | — |
| Apple Music: a song in your library (downloaded) plays from the library | done | — | — | — |
| 台語 數字練習 (算數 typed in spelling; 白還是文) — in 不熟's empty tile | done | todo | todo | — |
| 詞龍 (typed or handwritten — handwriting read by iOS Vision; every language) in 遊戲 | done | todo | todo | — |
| 熟悉 → a character level: the characters as a grid (like 認識的漢字) | done | todo | todo | — |
| 認識的漢字 → 猜字義 game (no status change; common characters more often) | done | todo | todo | — |
| App icon: light version (設定 → 顏色與外觀 → App 圖示) | done | todo | todo | — |
| 常用度: a hollow ring filled by % in colours along the 台語 tone colours | done | todo | todo | todo |
| 常用度 steps (依常用度列出, 新詞 topics) by how full the ring is: 80/60/40/20 % = places 136 / 1050 / 5024 / 18779 (was 1000/3000/8000/20000) | done | todo | todo | todo |
| 華語 readings: HSK words not in the 兩岸 dictionary get Taiwan readings per character (not where the reading really differs, 比比皆是) | done (Zh.swift fillTaiwan) | todo | todo | todo (build_safari) |
| YouTube: lyrics made from the video's own subtitles when LRCLIB has none, saved to the 歌詞 folder as "title - artist [yt-id].lrc" | done | — | todo | — |
| 台語 各地讀音 → 讀音從哪裡來: each 字's reading per place, by 腔, where it's from (辭典 / 推測 / 照字), and how many words have it (tap: the words with meanings) | done | todo | todo | — |
| Own words (自訂) in 華語, 粵語, 客語, 日語, 瑞典語 (word, reading, meaning, example), CSV export; keys "word\t<reading>#自" in Progress.own | done (no CSV import for these yet) | todo | todo | todo |
| Gemini (own API key, 設定 → 詞典): no search result → its guesses, shown as dictionary words (瑞典語: only when no English match either); 華語: add the term to 自訂; 本週學習 → 造句 (usage corrected, then the whole sentence) | done | todo | todo | — |
| First-run setup in steps: app language + 正體／簡體; meanings + spelling; each language's place (台語 腔口, 華語 讀音, 客語 腔); tone colours + 方音 options | done | todo | todo | — |
| 方音 option: light tone keeps its own tone mark or only ˙ (設定 → 語言與讀音 → 台語) | done | todo | todo | todo |
| 一起玩: two or more players nearby (MultipeerConnectivity: Wi-Fi / Bluetooth) take turns. Each picks their own way of answering and number of words and presses 準備好了; it starts when everyone has. On your turn a word from your own 練習範圍 / language is sent to the others only (never shown on your screen); they see its clues one at a time (讀音, then 意思, then 部首 when asked; 瑞典語: 意思, then letters) and the answer, and read the clues to you. You answer on your screen (手寫, 八選一 with sound-alike words, 打字) and press 完成; your answer shows on theirs and one of them presses 對 / 錯. 10 points, −3 per extra clue; most points wins. Words listed only once answered. Your answers count for 不熟 / 複習 | done (nearby only, iOS ↔ iOS) | todo | todo | — |
| Add-on (Safari copy): subtitles 轉成簡體; 拼音／注音 button in the subtitle bar; the gear opens a big 字幕設定 page | done (apple/FangfangSafari) | — | — | todo (Firefox build: bump the version and rebuild) |

## Asked for, not done yet (any platform)

Kept here so nothing is lost. Roughly from smallest to biggest.

- 台語 數字: (done on iOS) the rules, kept for the other versions: (白／文 readings, 量詞, 一百十 rule; math questions typed in spelling, tone marks optional;
  a second game for when 白 / 文 is used, with example words and sentences). Rules from the user, 2026-11-27:
  0 空 khọng; 1 一 ịt (量詞前 ji̍t); 2 二 łī (量詞前 兩 nn̄g); 3 sa̍ⁿ / 文 sa̍m; 4 xị / 文 sụ; 5 gōo / 文 ngòo;
  6 la̍k / 文 lio̍k; 7 qịt; 8 pẹh / 文 pạt; 9 kàu / 文 kiù; 10 za̍p / 文 xi̍p. 文 for phone numbers, ages, fixed
  expressions (四季). 11 za̍p ịt, 20 łī za̍p, 101 ji̍t pạh khọng łī, 110 ji̍t pạh ịt (一百十, never 一百一十),
  120 ji̍t pạh łī, 200 nn̄g pạh, 2000 nn̄g qi̍ng, 2002 nn̄g qi̍ng khọng łī, 2202 nn̄g qi̍ng nn̄g pẹh khọng lī,
  10 000 ji̍t bān. Above 10 a 量詞 after the number still takes 二, not 兩.
- Co-op game: over the internet (not only nearby), and across platforms (Android, desktop) — needs a server or a
  relay; the iOS nearby version's messages (CoopGame.swift, CoopMsg JSON) can be the format. Handwriting there
  with the full 手寫 tools (pen sizes, 延遲, 彩色) instead of the plain pad.
- Own words in 華語 … 瑞典語: CSV import (only export so far).
