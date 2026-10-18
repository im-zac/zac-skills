#!/bin/bash
# 向 telecipher 登錄 secret 需求並等待完成。值永遠不經過這支腳本。
# 用法：request.sh --path <path> --mode file|env [--key KEY] --description "<text>" [--session <name>] [--wait-minutes 120]
# stdout：REGISTERED <id> <path>，然後 FULFILLED <id> | CANCELLED <id> | TIMEOUT <id>
# exit：0 fulfilled｜2 缺 token／token 不被接受｜3 登錄被拒（400）｜4 連不上｜5 cancelled｜6 timeout｜7 參數錯｜8 需求不存在（被清除或 server 重啟後遺失）
set -u
URL="${TELECIPHER_URL:-http://127.0.0.1:9877}"
TOKEN_FILE="${TELECIPHER_TOKEN_FILE:-$HOME/.telecipher/token}"
PATH_ARG=""; MODE=""; KEY=""; DESC=""; SESSION=""; WAIT_MIN=120
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PATH_ARG="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --key) KEY="$2"; shift 2;;
    --description) DESC="$2"; shift 2;;
    --session) SESSION="$2"; shift 2;;
    --wait-minutes) WAIT_MIN="$2"; shift 2;;
    *) echo "未知參數：$1" >&2; exit 7;;
  esac
done
[ -n "$PATH_ARG" ] && [ -n "$MODE" ] && [ -n "$DESC" ] || { echo "需要 --path --mode --description" >&2; exit 7; }
[ "$MODE" = env ] && [ -z "$KEY" ] && { echo "env 模式需要 --key" >&2; exit 7; }
case "$WAIT_MIN" in ''|*[!0-9]*) echo "--wait-minutes 需為非負整數" >&2; exit 7;; esac
# 相對路徑以呼叫端 cwd 為準（server 端會把相對路徑當成相對 $HOME）
case "$PATH_ARG" in /*|~*) ;; *) PATH_ARG="$PWD/$PATH_ARG";; esac
[ -r "$TOKEN_FILE" ] || { echo "找不到 ${TOKEN_FILE}。請在 telecipher repo 跑 bun run setup。" >&2; exit 2; }
# token 不放進命令列參數（ps 看得到）：寫成 0600 的 header 檔，用 curl -H @file
HDR="$(mktemp)"; chmod 600 "$HDR"; trap 'rm -f "$HDR"' EXIT
printf 'x-telecipher-token: %s\n' "$(tr -d '\n' < "$TOKEN_FILE")" > "$HDR"

if [ -z "$SESSION" ]; then
  SESSION="$(tmux display-message -p '#S' 2>/dev/null || true)"
  [ -n "$SESSION" ] || SESSION="$(basename "$PWD")"
fi

# 跳脫 \ 與 "；換行改成空白（description 應為一句話）
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' '; }
BODY="{\"session\":\"$(json_escape "$SESSION")\",\"path\":\"$(json_escape "$PATH_ARG")\",\"mode\":\"$MODE\",\"description\":\"$(json_escape "$DESC")\""
[ -n "$KEY" ] && BODY="$BODY,\"key\":\"$(json_escape "$KEY")\""
BODY="$BODY}"

RESP="$(curl -s -w '\n%{http_code}' -X POST -H @"$HDR" -H 'content-type: application/json' -d "$BODY" "$URL/api/requests" 2>/dev/null)"
CODE="$(printf '%s' "$RESP" | tail -1)"
JSON="$(printf '%s' "$RESP" | sed '$d' | tr -d '\n')"
# 連線失敗時 curl 仍印 write-out，http_code 是 000
if [ -z "$CODE" ] || [ "$CODE" = "000" ]; then echo "連不上 telecipher（${URL}）。確認 daemon 有在跑。" >&2; exit 4; fi
if [ "$CODE" = "401" ]; then echo "token 不被接受。重跑 bun run setup 同步 ~/.telecipher/token。" >&2; exit 2; fi
if [ "$CODE" != "201" ]; then
  REASON="$(printf '%s' "$JSON" | sed -n 's/.*"reason": *"\([^"]*\)".*/\1/p')"
  echo "登錄被拒（HTTP ${CODE}）：${REASON:-$JSON}" >&2
  exit 3
fi
ID="$(printf '%s' "$JSON" | sed -n 's/.*"id": *"\([a-z2-7]*\)".*/\1/p')"
RPATH="$(printf '%s' "$JSON" | sed -n 's/.*"path": *"\([^"]*\)".*/\1/p')"
echo "REGISTERED $ID $RPATH"

DEADLINE=$(( $(date +%s) + WAIT_MIN * 60 ))
while :; do
  NOW=$(date +%s)
  [ "$NOW" -lt "$DEADLINE" ] || { echo "TIMEOUT $ID"; exit 6; }
  LEFT=$(( DEADLINE - NOW )); T=55; [ "$LEFT" -lt 55 ] && T=$LEFT
  WR="$(curl -s -w '\n%{http_code}' --max-time $((T + 10)) -H @"$HDR" "$URL/api/requests/$ID/wait?timeout=$T" 2>/dev/null)"
  WCODE="$(printf '%s' "$WR" | tail -1)"
  case "$WCODE" in
    404) echo "需求不存在（${ID}）：可能已被清除，或 server 重啟後遺失。若檔案已寫入就不必重試。" >&2; exit 8;;
    401) echo "token 不被接受。重跑 bun run setup 同步 ~/.telecipher/token。" >&2; exit 2;;
  esac
  STATUS="$(printf '%s' "$WR" | sed '$d' | tr -d '\n' | sed -n 's/.*"status": *"\([a-z]*\)".*/\1/p')"
  case "$STATUS" in
    fulfilled) echo "FULFILLED $ID"; exit 0;;
    cancelled) echo "CANCELLED $ID"; exit 5;;
    pending) ;;
    *) sleep 5;;   # 連線中斷或其他狀態碼：稍後重試，直到 deadline
  esac
done
