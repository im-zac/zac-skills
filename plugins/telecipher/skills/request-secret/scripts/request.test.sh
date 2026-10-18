#!/bin/bash
# 需要測試用 server（token devtoken、資料目錄導去 tmp）：
#   PORT=9879 NUXT_TELECIPHER_TOKEN=devtoken NUXT_TELECIPHER_DATA_DIR=/tmp/tc-data node .output/server/index.mjs
#   TELECIPHER_URL=http://127.0.0.1:9879 bash request.test.sh
set -u
URL="${TELECIPHER_URL:-http://127.0.0.1:9877}"
export TELECIPHER_URL="$URL"
HERE="$(cd "$(dirname "$0")" && pwd)"
SH="$HERE/request.sh"
TOKEN_FILE="$(mktemp)"; echo devtoken > "$TOKEN_FILE"
fail=0
check() { if [ "$1" = "$2" ]; then echo "ok   $3"; else echo "FAIL $3: got $1 want $2"; fail=1; fi }

TELECIPHER_TOKEN_FILE=/nonexistent "$SH" --path ~/tmp/x --mode file --description d >/dev/null 2>&1
check $? 2 "缺 token → exit 2"

TELECIPHER_URL=http://127.0.0.1:1 TELECIPHER_TOKEN_FILE="$TOKEN_FILE" "$SH" --path ~/tmp/x --mode file --description d >/dev/null 2>&1
check $? 4 "連不上 → exit 4"

TELECIPHER_TOKEN_FILE="$TOKEN_FILE" "$SH" --path ~/.ssh/x --mode file --description d >/dev/null 2>&1
check $? 3 "拒絕路徑 → exit 3"

TELECIPHER_TOKEN_FILE="$TOKEN_FILE" "$SH" --path ~/tmp/x --mode file --description d --wait-minutes 'a[$(touch /tmp/tc-injected)]' >/dev/null 2>&1
check $? 7 "wait-minutes 非整數 → exit 7"
[ ! -e /tmp/tc-injected ]; check $? 0 "wait-minutes 不會被當算式執行"

out=$(TELECIPHER_TOKEN_FILE="$TOKEN_FILE" "$SH" --path ~/tmp/telecipher-sh-test/.env --mode env --key K --description d --wait-minutes 0 2>/dev/null)
check $? 6 "wait 0 分 → TIMEOUT exit 6"
echo "$out" | grep -q '^REGISTERED [a-z2-7]\{12\} ' ; check $? 0 "印 REGISTERED"
echo "$out" | tail -1 | grep -q '^TIMEOUT ' ; check $? 0 "最後一行 TIMEOUT"
id=$(echo "$out" | grep '^REGISTERED' | awk '{print $2}')
curl -s -X DELETE -H 'x-telecipher-token: devtoken' "$URL/api/requests/$id" >/dev/null

# fulfill 路徑：背景跑 request.sh，1 秒後 fulfill
TELECIPHER_TOKEN_FILE="$TOKEN_FILE" "$SH" --path ~/tmp/telecipher-sh-test/.env --mode env --key K2 --description d --wait-minutes 1 > /tmp/tc-req-out.txt 2>/dev/null &
pid=$!
sleep 1
id=$(grep '^REGISTERED' /tmp/tc-req-out.txt | awk '{print $2}')
curl -s -X POST -H 'x-telecipher-token: devtoken' -H 'content-type: application/json' -d '{"value":"v"}' "$URL/api/requests/$id/fulfill" >/dev/null
wait $pid; check $? 0 "fulfill → exit 0"
tail -1 /tmp/tc-req-out.txt | grep -q "^FULFILLED $id" ; check $? 0 "最後一行 FULFILLED"

# 相對路徑：以呼叫端 cwd 為準，不是 server 的 $HOME
mkdir -p ~/tmp/telecipher-sh-test/proj
out=$(cd ~/tmp/telecipher-sh-test/proj && TELECIPHER_TOKEN_FILE="$TOKEN_FILE" "$SH" --path .env --mode env --key R --description d --wait-minutes 0 2>/dev/null)
echo "$out" | grep -q "^REGISTERED [a-z2-7]\{12\} $HOME/tmp/telecipher-sh-test/proj/.env$" ; check $? 0 "相對路徑 → \$PWD 下"
id=$(echo "$out" | grep '^REGISTERED' | awk '{print $2}')
curl -s -X DELETE -H 'x-telecipher-token: devtoken' "$URL/api/requests/$id" >/dev/null

# wait 迴圈遇 404／401：用 stub server 模擬（登錄 201，wait 回指定狀態碼）
# macOS 沒有 timeout：背景跑、超時就 kill，exit 124
limit() { local secs=$1; shift; "$@" & local p=$!; ( sleep "$secs"; kill "$p" 2>/dev/null ) & local w=$!; wait "$p" 2>/dev/null; local rc=$?; kill "$w" 2>/dev/null; wait "$w" 2>/dev/null; [ $rc -eq 143 ] && rc=124; return $rc; }
stub() {  # $1 = wait 回的 http code
  node -e '
    const code = +process.argv[1]
    require("http").createServer((req, res) => {
      if (req.method === "POST") { res.writeHead(201, {"content-type":"application/json"}); res.end(JSON.stringify({id:"abcdefghijkl",path:"/x"})); return }
      res.writeHead(code); res.end()
    }).listen(9878, "127.0.0.1")
  ' "$1" >/dev/null 2>&1 &
  echo $!
}
spid=$(stub 404); sleep 0.5
TELECIPHER_URL=http://127.0.0.1:9878 TELECIPHER_TOKEN_FILE="$TOKEN_FILE" limit 20 "$SH" --path ~/tmp/x --mode file --description d --wait-minutes 1 >/dev/null 2>/tmp/tc-err.txt
check $? 8 "wait 回 404 → exit 8，不空轉"
grep -q '需求不存在' /tmp/tc-err.txt; check $? 0 "404 有說明訊息"
kill $spid 2>/dev/null; wait $spid 2>/dev/null
spid=$(stub 401); sleep 0.5
TELECIPHER_URL=http://127.0.0.1:9878 TELECIPHER_TOKEN_FILE="$TOKEN_FILE" limit 20 "$SH" --path ~/tmp/x --mode file --description d --wait-minutes 1 >/dev/null 2>&1
check $? 2 "wait 回 401 → exit 2"
kill $spid 2>/dev/null; wait $spid 2>/dev/null

rm -rf ~/tmp/telecipher-sh-test /tmp/tc-req-out.txt /tmp/tc-err.txt "$TOKEN_FILE"
exit $fail
