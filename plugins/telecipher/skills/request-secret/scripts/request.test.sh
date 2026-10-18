#!/bin/bash
# 需要 dev server：NUXT_TELECIPHER_TOKEN=devtoken bun run dev（telecipher repo）
set -u
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

out=$(TELECIPHER_TOKEN_FILE="$TOKEN_FILE" "$SH" --path ~/tmp/telecipher-sh-test/.env --mode env --key K --description d --wait-minutes 0 2>/dev/null)
check $? 6 "wait 0 分 → TIMEOUT exit 6"
echo "$out" | grep -q '^REGISTERED [a-z2-7]\{12\} ' ; check $? 0 "印 REGISTERED"
echo "$out" | tail -1 | grep -q '^TIMEOUT ' ; check $? 0 "最後一行 TIMEOUT"
id=$(echo "$out" | grep '^REGISTERED' | awk '{print $2}')
curl -s -X DELETE -H 'x-telecipher-token: devtoken' "http://127.0.0.1:9877/api/requests/$id" >/dev/null

# fulfill 路徑：背景跑 request.sh，1 秒後 fulfill
TELECIPHER_TOKEN_FILE="$TOKEN_FILE" "$SH" --path ~/tmp/telecipher-sh-test/.env --mode env --key K2 --description d --wait-minutes 1 > /tmp/tc-req-out.txt 2>/dev/null &
pid=$!
sleep 1
id=$(grep '^REGISTERED' /tmp/tc-req-out.txt | awk '{print $2}')
curl -s -X POST -H 'x-telecipher-token: devtoken' -H 'content-type: application/json' -d '{"value":"v"}' "http://127.0.0.1:9877/api/requests/$id/fulfill" >/dev/null
wait $pid; check $? 0 "fulfill → exit 0"
tail -1 /tmp/tc-req-out.txt | grep -q "^FULFILLED $id" ; check $? 0 "最後一行 FULFILLED"
rm -rf ~/tmp/telecipher-sh-test /tmp/tc-req-out.txt "$TOKEN_FILE"
exit $fail
