# 方方詞卡 relay · 連線伺服器

**English below.**

「一起玩」和「詞龍」可以透過網路和別人玩（iPhone／iPad、Android、Windows／Mac 都可以一起）。訊息經過這個小小的伺服器轉送：你自己在 Cloudflare 的免費帳號上放一次就好。

- 每個房間用「房間代碼」進去；伺服器只看得到代碼算出來的編號，看不到代碼。
- 每則訊息在 App 裡就用代碼算出來的金鑰加密（AES-GCM），伺服器只是轉送它看不懂的資料，什麼都不存。
- 一個房間最多 16 個人。

## 放上去

1. 申請 Cloudflare 帳號（免費）：<https://dash.cloudflare.com/sign-up>
2. 電腦上要有 Node.js（<https://nodejs.org>）。
3. 在這個資料夾（`relay`）打開終端機，執行：

   ```
   npx wrangler login
   npx wrangler deploy
   ```

4. 最後會顯示網址，像 `https://fangfang-relay.你的名字.workers.dev`。
5. App 裡：設定 → 一起玩 → 連線伺服器，貼上這個網址。和你一起玩的人也貼同一個網址。

## English

Play 一起玩 and 詞龍 with others over the internet (iPhone / iPad, Android and Windows / Mac together). Messages go through this small relay, which you put on your own free Cloudflare account once.

- A room is joined with a room code; the relay only sees a number made from the code, never the code.
- Every message is encrypted in the app with a key made from the code (AES-GCM); the relay only passes on bytes it can't read, and stores nothing.
- At most 16 players a room.

### Deploy

1. A Cloudflare account (free): <https://dash.cloudflare.com/sign-up>
2. Node.js on the computer (<https://nodejs.org>).
3. In this folder (`relay`), in a terminal:

   ```
   npx wrangler login
   npx wrangler deploy
   ```

4. It shows an address like `https://fangfang-relay.your-name.workers.dev`.
5. In the app: Settings → 一起玩 → Relay server, paste the address. The people you play with paste the same one.
