#!/usr/bin/env bash
# so.sh 的測試：用假 claude 和真的 tmux，不花 token。執行：bash tests/so_test.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SO="$ROOT/skills/session-orchestrator/scripts/so.sh"
TMP=$(cd "$(mktemp -d)" && pwd -P)
export SO_SESSIONS_DIR="$TMP/sessions" SO_STATE_DIR="$TMP/state" SO_CLAUDE_JSON="$TMP/claude.json"
export SO_CLAUDE_BIN="$ROOT/tests/fake-claude.sh" FAKE_LOG_DIR="$TMP/log" SO_WAIT_SECS=5
export SO_PASS_ENV="SO_SESSIONS_DIR FAKE_LOG_DIR FAKE_EXIT"
mkdir -p "$SO_SESSIONS_DIR" "$FAKE_LOG_DIR"
echo '{"projects":{}}' > "$SO_CLAUDE_JSON"

REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
PLAIN="$TMP/plain"; mkdir -p "$PLAIN"

pass=0; fail=0
t() { local name="$1"; shift; if "$@"; then pass=$((pass + 1)); echo "ok   $name"; else fail=$((fail + 1)); echo "FAIL $name"; fi; }
code() { local want="$1"; shift; "$@" >/dev/null 2>&1; [ "$?" -eq "$want" ]; }
cleanup() {
  local s
  for s in $(tmux ls -F '#{session_name}' 2>/dev/null | grep '^so-t-'); do tmux kill-session -t "=$s"; done
  pkill -f "$ROOT/tests/fake-claude.sh" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT
trust_repo() { jq -n --arg p "$REPO" '{projects: {($p): {hasTrustDialogAccepted: true}}}' > "$SO_CLAUDE_JSON"; }

# --- uuid / trust ---
u=$("$SO" uuid)
t "uuid 是小寫 36 字元" [ "$(printf '%s' "$u" | grep -cE '^[0-9a-f-]{36}$')" = 1 ]
t "未信任的 repo 回 2" code 2 "$SO" trust "$REPO"
t "非 git 目錄回 not-git" [ "$("$SO" trust "$PLAIN")" = "not-git" ]
trust_repo
t "已信任的 repo 回 trusted" [ "$("$SO" trust "$REPO")" = "trusted" ]

# --- find / alive 忽略 pid 已死的舊項目 ---
echo '{"pid": 999999, "sessionId": "dead-id", "name": "so-t-dead", "cwd": "/"}' > "$SO_SESSIONS_DIR/999999.json"
t "pid 已死的項目算 dead" code 6 "$SO" alive dead-id
t "byname 找不到 pid 已死的項目" code 6 "$SO" byname so-t-dead
# pid 被別的 process 重用（重開機後常見）：procStart 不同就算 dead
echo "{\"pid\": $$, \"procStart\": \"Thu Jan  1 00:00:00 2020\", \"sessionId\": \"reused-id\", \"name\": \"so-t-reused\", \"cwd\": \"/\"}" > "$SO_SESSIONS_DIR/1.json"
t "pid 還活著但 procStart 不同的項目算 dead" code 6 "$SO" alive reused-id
t "byname 找不到 procStart 不同的項目" code 6 "$SO" byname so-t-reused

# --- spawn ---
PROMPT="$TMP/prompt.txt"
printf '/orchestrated-session start https://claude.ai/artifact/x session-orchestrator so-t-a\n任務：修 "引號" 與 $HOME 與 `反引號` 的 bug\n' > "$PROMPT"
t "名稱有大寫或底線回 1" code 1 "$SO" spawn Bad_Name "$REPO" "$PROMPT"
echo '{"projects":{}}' > "$SO_CLAUDE_JSON"
t "未信任的 repo 不能 spawn（回 2）" code 2 "$SO" spawn so-t-a "$REPO" "$PROMPT"
t "未信任時沒有建立 tmux session" code 1 tmux has-session -t "=so-t-a"
trust_repo
out=$("$SO" spawn so-t-a "$REPO" "$PROMPT")
A_ID=$(printf '%s' "$out" | jq -r '.sessionId')
t "spawn 回傳 worktree 的 cwd" [ "$(printf '%s' "$out" | jq -r '.cwd')" = "$REPO/.claude/worktrees/so-t-a" ]
t "spawn 回傳 repo 根目錄" [ "$(printf '%s' "$out" | jq -r '.repo')" = "$REPO" ]
t "tmux session 已建立" tmux has-session -t "=so-t-a"
t "claude 收到 -w -n --session-id" [ "$(sed -n 1,6p "$FAKE_LOG_DIR/so-t-a.args" | tr '\n' ' ')" = "-w so-t-a -n so-t-a --session-id $A_ID " ]
t "prompt 原樣送達（換行、引號、\$、反引號）" [ "$(cat "$FAKE_LOG_DIR/so-t-a.prompt")" = "$(cat "$PROMPT")" ]
t "alive 回 alive" [ "$("$SO" alive "$A_ID")" = "alive" ]
t "byname 找得到" [ "$("$SO" byname so-t-a | jq -r '.sessionId')" = "$A_ID" ]
echo "{\"pid\": 999998, \"sessionId\": \"$A_ID\", \"name\": \"so-t-a\", \"cwd\": \"/\"}" > "$SO_SESSIONS_DIR/0.json"
t "同 sessionId 的舊項目不影響活著的那筆" [ "$("$SO" find "$A_ID" | jq -r '.pid')" != 999998 ]
rm -f "$SO_SESSIONS_DIR/0.json"
ps_start=$(LC_ALL=C TZ=UTC ps -o lstart= -p $$)
jq -n --argjson pid $$ --arg ps "$ps_start" '{pid: $pid, procStart: $ps, sessionId: "dup-id", name: "so-t-a", cwd: "/"}' > "$SO_SESSIONS_DIR/2.json"
t "兩個活著的同名項目時 byname 回 8" code 8 "$SO" byname so-t-a
t "procStart 相符的項目算 alive" [ "$("$SO" alive dup-id)" = "alive" ]
rm -f "$SO_SESSIONS_DIR/2.json"
t "同名再 spawn 回 3" code 3 "$SO" spawn so-t-a "$REPO" "$PROMPT"
out=$("$SO" spawn so-t-plain "$PLAIN" "$PROMPT")
t "非 git 目錄不加 -w" [ "$(sed -n 1p "$FAKE_LOG_DIR/so-t-plain.args")" = "-n" ]
t "非 git 目錄的 cwd 就是該目錄" [ "$(printf '%s' "$out" | jq -r '.cwd')" = "$PLAIN" ]
err=$(FAKE_EXIT=1 "$SO" spawn so-t-early "$REPO" "$PROMPT" 2>&1 >/dev/null); rc=$?
t "claude 立刻結束時回 4" [ "$rc" -eq 4 ]
t "錯誤訊息附上 pane 畫面" [ "$(printf '%s' "$err" | grep -c '\[so\] claude exited')" -ge 1 ]

# --- stop ---
t "stop 回 stopped" [ "$("$SO" stop "$A_ID" so-t-a)" = "stopped" ]
t "stop 後 pid 不在" code 6 "$SO" alive "$A_ID"
t "stop 後 tmux session 不在" code 1 tmux has-session -t "=so-t-a"
t "stop 後 worktree 還在" [ -d "$REPO/.claude/worktrees/so-t-a" ]
t "對已結束的 session 再 stop 也成功" [ "$("$SO" stop "$A_ID" so-t-a)" = "stopped" ]
"$SO" stop no-such-id so-t-early >/dev/null
t "stop 會關掉沒有活著 pid 的同名 tmux session" code 1 tmux has-session -t "=so-t-early"

# --- resume ---
RPROMPT="$TMP/resume.txt"
printf '/orchestrated-session resume https://claude.ai/artifact/x session-orchestrator so-t-a\n' > "$RPROMPT"
WT="$REPO/.claude/worktrees/so-t-a"
t "cwd 不存在時回 5" code 5 "$SO" resume so-t-a "$A_ID" "$TMP/nope" "$RPROMPT"
out=$("$SO" resume so-t-a "$A_ID" "$WT" "$RPROMPT")
t "resume 回傳同一個 sessionId" [ "$(printf '%s' "$out" | jq -r '.sessionId')" = "$A_ID" ]
t "resume 的 cwd 是 worktree" [ "$(printf '%s' "$out" | jq -r '.cwd')" = "$WT" ]
t "claude 收到 -r <id> -n <name>" [ "$(sed -n 1,4p "$FAKE_LOG_DIR/so-t-a.args" | tr '\n' ' ')" = "-r $A_ID -n so-t-a " ]
t "resume prompt 原樣送達" [ "$(cat "$FAKE_LOG_DIR/so-t-a.prompt")" = "$(cat "$RPROMPT")" ]
t "還在執行時再 resume 回 7" code 7 "$SO" resume so-t-a "$A_ID" "$WT" "$RPROMPT"
"$SO" stop "$A_ID" so-t-a >/dev/null
tmux new-session -d -s so-t-a
t "同名 tmux session 存在時 resume 回 3" code 3 "$SO" resume so-t-a "$A_ID" "$WT" "$RPROMPT"

# --- stop 只關 orchestrator 開的 tmux session ---
tmux new-session -d -s so-t-foreign
"$SO" stop no-such-id so-t-foreign >/dev/null 2>&1
t "stop 不關使用者自己開的同名 tmux session" tmux has-session -t "=so-t-foreign"
tmux kill-session -t "=so-t-foreign"

# --- child-cmd：依安裝方式印出子 skill 的指令 ---
PL="$TMP/plugins/cache/m/session-orchestrator/1.0.0"
mkdir -p "$PL/.claude-plugin" "$PL/skills/session-orchestrator/scripts"
cp "$SO" "$PL/skills/session-orchestrator/scripts/so.sh"
echo '{"name": "session-orchestrator"}' > "$PL/.claude-plugin/plugin.json"
t "plugin 安裝時印出 /<plugin>:orchestrated-session" [ "$(bash "$PL/skills/session-orchestrator/scripts/so.sh" child-cmd)" = "/session-orchestrator:orchestrated-session" ]
t "用相對路徑執行也認得 plugin 安裝" [ "$(cd "$PL" && bash skills/session-orchestrator/scripts/so.sh child-cmd)" = "/session-orchestrator:orchestrated-session" ]
SK="$TMP/home/.claude/skills"
mkdir -p "$SK"
ln -s "$PL/skills/session-orchestrator" "$SK/session-orchestrator"
t "從 ~/.claude/skills 的 symlink 執行時印出 /orchestrated-session" [ "$(bash "$SK/session-orchestrator/scripts/so.sh" child-cmd)" = "/orchestrated-session" ]

# --- console-url：總表網址 ---
t "還沒存網址時 console-url 回 6" code 6 "$SO" console-url
t "網址不是 https://claude.ai/ 開頭時回 1" code 1 "$SO" console-url http://example.com/x
"$SO" console-url https://claude.ai/artifact/abc >/dev/null
t "存過後 console-url 印出網址" [ "$("$SO" console-url)" = "https://claude.ai/artifact/abc" ]

# --- 結果 ---
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
