#!/bin/bash
# 方方詞卡: put the relay (連線伺服器) on your own free Cloudflare account. Double-click this file on a Mac.
# It logs in to Cloudflare (a browser page opens: press Allow), uploads the relay, and copies its address.
cd "$(dirname "$0")" || exit 1
echo "方方詞卡 · 連線伺服器"
echo
if ! command -v npx >/dev/null 2>&1; then
  echo "要先安裝 Node.js（https://nodejs.org，下載 LTS 版，裝好以後再按兩下這個檔案）。"
  echo "Node.js is needed first (https://nodejs.org, the LTS version). Install it, then double-click this file again."
  open "https://nodejs.org"
  read -n 1 -s -r -p "按任一鍵關掉 / Press any key to close"
  exit 1
fi
echo "1/2 登入 Cloudflare：瀏覽器會打開一個頁面，按 Allow。"
echo "    Logging in to Cloudflare: a browser page opens, press Allow."
npx --yes wrangler login || { echo; echo "登入沒有成功 / Login failed."; read -n 1 -s -r -p "按任一鍵關掉 / Press any key to close"; exit 1; }
echo
echo "2/2 上傳中…（第一次可能會問 workers.dev 的名字：打一個英文名字，例如你的名字，再按 Return）"
echo "    Uploading… (the first time it may ask for a workers.dev name: type one, such as your name, and press Return)"
npx --yes wrangler deploy 2>&1 | tee /tmp/fangfang-relay-deploy.log
url=$(grep -oE 'https://[a-zA-Z0-9.-]+\.workers\.dev' /tmp/fangfang-relay-deploy.log | head -1)
echo
if [ -n "$url" ]; then
  printf "%s" "$url" | pbcopy
  echo "完成！網址已經複製了：$url"
  echo "在 App 的 設定 → 卡片與練習 → 一起玩 → 連線伺服器 貼上。也把這個網址傳給一起玩的人。"
  echo "Done! The address is copied: $url"
  echo "Paste it in the app: 設定 → 卡片與練習 → 一起玩 → 連線伺服器, and send it to the people you play with."
else
  echo "沒有找到網址，上面有錯誤訊息。可以把它貼給 Claude 看。"
  echo "No address found; the messages above say what went wrong (you can paste them to Claude)."
fi
echo
read -n 1 -s -r -p "按任一鍵關掉 / Press any key to close"
