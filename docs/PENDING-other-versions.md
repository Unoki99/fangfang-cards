# Changes waiting for the other versions

Rounds that were done on one platform first. Each item: what changed, where it was done, and what the other
versions still need. When an item has been done everywhere, delete it here.

## Round of 2026-11-27 (iPhone / iPad first, then Android and desktop)

Done on iOS, Android and desktop this round; what's left is the **Firefox add-on**. (Items done everywhere were
taken out. Also done everywhere: 一起玩 and 詞龍 over the internet, across iOS, Android and desktop, through the relay
in relay/, which has to be deployed once on your own Cloudflare account; see relay/README.md.)
Android and desktop are one code base (android/app/src/main, Kotlin / Compose; windows/ builds the same code as a
computer program), so each item is ported to both at once.


| Item | iOS | Android | Desktop | Add-on |
|---|---|---|---|---|
| 華語 pinyin search: lü / ǜ read as v (lv finds 綠; lu still finds lü words after the lu ones) | done | done | done | todo |
| 方音 light tone keeps the syllable's own tone mark (˙ㄐㄧㆵ̇˙ㄍㄨㄚˋ) | done | done | done | todo |
| 客語 方音符號: ii ㄭ, m ㆬ, ng ㆭ, 入聲 ㆴㆵㆻ (陰入) / ㆴ̇ㆵ̇ㆻ̇ (陽入) | done (at display; the install table hz still has the old ones) | done | done | todo |
| 常用度: a hollow ring filled by %, the colour from full to empty pink, red, orange, yellow, green, teal, blue, purple (shades between); the 常用度 icons (依常用度列出, 學習紀錄, the steps) are the ring too | done | done | done | todo |
| 常用度 steps (依常用度列出, 新詞 topics) by how full the ring is: 80/60/40/20 % = places 136 / 1050 / 5024 / 18779 (was 1000/3000/8000/20000) | done | done | done | todo |
| 華語 readings: HSK words not in the 兩岸 dictionary get Taiwan readings per character (not where the reading really differs, 比比皆是) | done (Zh.swift fillTaiwan) | done | done | todo (build_safari) |
| Own words (自訂) in 華語, 粵語, 客語, 日語, 瑞典語 (word, reading, meaning, example), CSV export; keys "word\t<reading>#自" in Progress.own | done (no CSV import for these yet) | done | done | todo |
| 方音 option: light tone keeps its own tone mark or only ˙ (設定 → 語言與讀音 → 台語) | done | done | done | todo |
| Add-on (Safari copy): subtitles 轉成簡體; 拼音／注音 button in the subtitle bar; the gear opens a big 字幕設定 page | done (apple/FangfangSafari) | — | — | todo (Firefox build: bump the version and rebuild) |
| 英語 (a 7th language): ECDICT → en.json (Install/english.js, tools/build_english.py the same on the Mac): English, Chinese (正體, CC-CEDICT pairs) and Swedish (Folkets lexikon reversed) meanings, chosen in 設定; British (ECDICT) and American (CMUdict) IPA; forms; Folkets' example sentences; word lists 常用度 (groups of 500), Collins, 考試 (中考 … GRE), Oxford 3000; key "word\t英", orange | done | — (desktop only, like 瑞典語) | done | done (eng: its own shards d-eng-*; build_firefox.sh copies english.js) |
| 英語 and 瑞典語: the Swedish meanings as their own numbered column beside English and Chinese; 一起玩 is 八選一 among words spelt alike, or spelling it (clues: meaning, IPA, letters) | done | — / done (瑞典語) | done | — |
| 我的進度: 選擇 several levels and mark all their words 熟悉 at once (asked on the page) | done | done | done | — |
| Add-on: English words no longer looked up through the Chinese languages (英文查中文 taken out, no d-en-* files); English subtitles' Chinese from the 英語 dictionary | — | — | — | done in apple/FangfangSafari |
| Gemini: a suggested word the dictionary doesn't have can be saved as your own word (＋), its meaning what was searched | done | done | done | — |

## Asked for, not done yet (any platform)

Kept here so nothing is lost. Roughly from smallest to biggest.

- Own words in 華語 … 瑞典語: CSV import (only export so far).
