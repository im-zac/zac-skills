#!/usr/bin/env bash
# so.sh：session-orchestrator 的 shell 操作。只做確定性的事：檢查、啟動、等待、結束。
# 相容 macOS 內建 bash 3.2。
# 退出碼：0 成功｜1 用法錯誤｜2 repo 未接受信任｜3 tmux 名稱已被使用｜4 逾時｜5 目錄不存在｜6 找不到活著的 session｜7 session 還在執行｜8 同名的活著 session 不只一個
set -u

SESSIONS_DIR="${SO_SESSIONS_DIR:-$HOME/.claude/sessions}"
CLAUDE_JSON="${SO_CLAUDE_JSON:-$HOME/.claude.json}"
CLAUDE_BIN="${SO_CLAUDE_BIN:-$(command -v claude)}"
STATE_DIR="${SO_STATE_DIR:-$HOME/.claude/session-orchestrator}"
WAIT_SECS="${SO_WAIT_SECS:-30}"
PASS_ENV="${SO_PASS_ENV:-}"

die() { echo "so: $2" >&2; exit "$1"; }

valid_name() {
  case "$1" in
    ''|-*|*[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

cmd_uuid() { uuidgen | tr 'A-Z' 'a-z'; }

cmd_trust() {
  local repo="$1" root v
  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo "not-git"; return 0; fi
  root=$(git -C "$repo" rev-parse --show-toplevel)
  v=$(jq -r --arg p "$root" '.projects[$p].hasTrustDialogAccepted // false' "$CLAUDE_JSON" 2>/dev/null)
  if [ "$v" = "true" ]; then echo "trusted"; return 0; fi
  echo "untrusted"
  return 2
}

# squeeze：把連續空白縮成一個，去掉頭尾空白（ps 會在個位數日期前補空白、行尾留空白）。
squeeze() { tr -s ' ' | sed 's/^ //; s/ $//'; }

# is_live <registry 檔>：pid 還活著，而且有 procStart 時要和該 pid 的啟動時間相同（pid 可能被別的 process 重用）。
is_live() {
  local pid want got
  pid=$(jq -r '.pid' "$1")
  kill -0 "$pid" 2>/dev/null || return 1
  want=$(jq -r '.procStart // empty' "$1" | squeeze)
  [ -z "$want" ] && return 0
  got=$(LC_ALL=C TZ=UTC ps -o lstart= -p "$pid" 2>/dev/null | squeeze)
  [ "$want" = "$got" ]
}

# live_entries <欄位> <值>：每行印出一筆欄位相符、而且還活著的 registry 項目。
live_entries() {
  local field="$1" value="$2" f
  for f in "$SESSIONS_DIR"/*.json; do
    [ -e "$f" ] || continue
    jq -e --arg k "$field" --arg v "$value" '.[$k] == $v' "$f" >/dev/null 2>&1 || continue
    is_live "$f" && jq -c '{pid, sessionId, name, cwd, status, statusUpdatedAt}' "$f"
  done
  return 0
}

# find_live <欄位> <值>：印出第一筆相符而且還活著的項目；沒有就回 6。
find_live() {
  local j
  j=$(live_entries "$1" "$2" | head -n 1)
  [ -n "$j" ] || return 6
  printf '%s\n' "$j"
}

# find_unique <欄位> <值>：同 find_live，但有兩筆以上時回 8。
find_unique() {
  local j n
  j=$(live_entries "$1" "$2")
  n=$(printf '%s' "$j" | grep -c .)
  [ "$n" -eq 0 ] && return 6
  [ "$n" -gt 1 ] && die 8 "有 ${n} 個活著的 session 叫 $2：$(printf '%s' "$j" | jq -r '.sessionId' | tr '\n' ' ')"
  printf '%s\n' "$j"
}

# wait_live <sessionId>：最多等 WAIT_SECS 秒，直到 registry 出現活著的項目。
wait_live() {
  local i=0
  while [ "$i" -lt $((WAIT_SECS * 2)) ]; do
    find_live sessionId "$1" && return 0
    sleep 0.5
    i=$((i + 1))
  done
  return 4
}

# launcher <name> <prompt 檔> <claude 參數...>：產生啟動腳本並印出路徑。
# claude 在 30 秒內結束時，腳本保留 pane 10 分鐘，讓 orchestrator 讀得到錯誤訊息。
launcher() {
  local name="$1" pf="$2" f v isset val
  shift 2
  mkdir -p "$STATE_DIR/launch"
  f="$STATE_DIR/launch/$name.sh"
  {
    echo '#!/usr/bin/env bash'
    for v in $PASS_ENV; do
      eval "isset=\${$v+x}"
      if [ -n "$isset" ]; then
        eval "val=\$$v"
        printf 'export %s=%q\n' "$v" "$val"
      fi
    done
    echo 'start=$(date +%s)'
    printf '%q ' "$CLAUDE_BIN" "$@"
    printf '"$(cat %q)"\n' "$pf"
    echo 'rc=$?'
    echo 'if [ $(( $(date +%s) - start )) -lt 30 ]; then echo "[so] claude exited rc=$rc"; sleep 600; fi'
  } > "$f"
  echo "$f"
}

# model_args <model> <effort>：檢查後設定 MODEL_ARGS（傳給 claude 的 --model、--effort）。空字串表示不指定。
model_args() {
  MODEL_ARGS=()
  case "$1" in
    '') ;;
    *[!a-zA-Z0-9.-]*) die 1 "模型名稱只能用英數、. 與 -：$1" ;;
    *) MODEL_ARGS+=(--model "$1") ;;
  esac
  case "$2" in
    '') ;;
    low|medium|high|xhigh|max) MODEL_ARGS+=(--effort "$2") ;;
    *) die 1 "effort 只能是 low、medium、high、xhigh、max：$2" ;;
  esac
}

pane_tail() { tmux capture-pane -p -t "=$1:" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -5; }

cmd_spawn() {
  [ $# -ge 3 ] && [ $# -le 5 ] || die 1 "用法：so.sh spawn <name> <repo> <prompt 檔> [<model>] [<effort>]"
  local name="$1" repo="$2" pf="$3" trust dir uuid lf j
  valid_name "$name" || die 1 "名稱只能用小寫英數與 -，而且不能以 - 開頭：$name"
  model_args "${4:-}" "${5:-}"
  [ -d "$repo" ] || die 5 "目錄不存在：$repo"
  [ -f "$pf" ] || die 1 "prompt 檔不存在：$pf"
  [ -n "$CLAUDE_BIN" ] || die 1 "找不到 claude 執行檔"
  if tmux has-session -t "=$name" 2>/dev/null; then die 3 "tmux session 已存在：$name"; fi
  trust=$(cmd_trust "$repo")
  [ "$trust" = "untrusted" ] && die 2 "repo 還沒接受資料夾信任：$repo"
  uuid=$(cmd_uuid)
  mkdir -p "$STATE_DIR/launch"
  cp "$pf" "$STATE_DIR/launch/$name.prompt"
  if [ "$trust" = "trusted" ]; then
    dir=$(git -C "$repo" rev-parse --show-toplevel)
    lf=$(launcher "$name" "$STATE_DIR/launch/$name.prompt" -w "$name" -n "$name" --session-id "$uuid" ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"})
  else
    dir=$(cd "$repo" && pwd -P)
    lf=$(launcher "$name" "$STATE_DIR/launch/$name.prompt" -n "$name" --session-id "$uuid" ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"})
  fi
  tmux new-session -d -s "$name" -c "$dir" "bash $(printf '%q' "$lf")" || die 1 "tmux new-session 失敗：$name"
  j=$(wait_live "$uuid") || die 4 "${WAIT_SECS} 秒內沒有在 registry 看到 ${uuid}（tmux session ${name} 保留著）。pane 最後幾行：$(pane_tail "$name")"
  printf '%s' "$j" | jq -c --arg repo "$dir" --arg tmux "$name" '. + {repo: $repo, tmux: $tmux}'
}

cmd_stop() {
  [ $# -eq 2 ] || die 1 "用法：so.sh stop <sessionId> <name>"
  local id="$1" name="$2" j pid i=0
  valid_name "$name" || die 1 "名稱格式錯誤：${name}"
  if j=$(find_live sessionId "$id"); then
    pid=$(printf '%s' "$j" | jq -r '.pid')
    kill -TERM "$pid" 2>/dev/null
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
    if kill -0 "$pid" 2>/dev/null; then die 4 "pid ${pid} 在 10 秒內沒有結束"; fi
  fi
  if tmux has-session -t "=$name" 2>/dev/null; then
    if tmux display-message -p -t "=$name:" '#{pane_start_command}' 2>/dev/null | grep -qF "$STATE_DIR/launch/$name.sh"; then
      tmux kill-session -t "=$name"
    else
      echo "so: tmux session ${name} 不是 orchestrator 開的，保留著" >&2
    fi
  fi
  echo "stopped"
}

cmd_resume() {
  [ $# -ge 4 ] && [ $# -le 6 ] || die 1 "用法：so.sh resume <name> <sessionId> <cwd> <prompt 檔> [<model>] [<effort>]"
  local name="$1" id="$2" cwd="$3" pf="$4" lf j
  valid_name "$name" || die 1 "名稱格式錯誤：${name}"
  model_args "${5:-}" "${6:-}"
  [ -d "$cwd" ] || die 5 "cwd 不存在：${cwd}"
  [ -f "$pf" ] || die 1 "prompt 檔不存在：${pf}"
  [ -n "$CLAUDE_BIN" ] || die 1 "找不到 claude 執行檔"
  if find_live sessionId "$id" >/dev/null; then die 7 "session 還在執行：${id}"; fi
  if tmux has-session -t "=$name" 2>/dev/null; then die 3 "tmux session 已存在：${name}"; fi
  mkdir -p "$STATE_DIR/launch"
  cp "$pf" "$STATE_DIR/launch/$name.prompt"
  lf=$(launcher "$name" "$STATE_DIR/launch/$name.prompt" -r "$id" -n "$name" ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"})
  tmux new-session -d -s "$name" -c "$cwd" "bash $(printf '%q' "$lf")" || die 1 "tmux new-session 失敗：${name}"
  j=$(wait_live "$id") || die 4 "${WAIT_SECS} 秒內沒有在 registry 看到 ${id}（tmux session ${name} 保留著）。pane 最後幾行：$(pane_tail "$name")"
  printf '%s' "$j" | jq -c --arg tmux "$name" '. + {tmux: $tmux}'
}

# child-cmd：印出子 skill 的指令。從 plugin 安裝執行時加上 plugin 名稱前綴。
# 路徑取自 $0 原樣，不解開 symlink：從 ~/.claude/skills/ 的 symlink 執行時算一般安裝。
cmd_child_cmd() {
  local skills_dir root pj plugin
  skills_dir="${0%/*/*/*}"
  case "$skills_dir" in */*) root="${skills_dir%/*}" ;; *) root="." ;; esac
  pj="$root/.claude-plugin/plugin.json"
  if [ "${skills_dir##*/}" = "skills" ] && [ -f "$pj" ]; then
    plugin=$(jq -r '.name // empty' "$pj")
    [ -n "$plugin" ] && { echo "/${plugin}:orchestrated-session"; return 0; }
  fi
  echo "/orchestrated-session"
}

# console-url [<網址>]：讀出或存下總表網址。
cmd_console_url() {
  local f="$STATE_DIR/console-url"
  if [ $# -eq 0 ]; then
    [ -s "$f" ] || return 6
    cat "$f"
    return 0
  fi
  case "$1" in https://claude.ai/*) ;; *) die 1 "網址要以 https://claude.ai/ 開頭：$1" ;; esac
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$1" > "$f"
  echo "$1"
}

sub="${1:-}"
[ $# -gt 0 ] && shift
case "$sub" in
  uuid) cmd_uuid ;;
  trust) [ $# -eq 1 ] || die 1 "用法：so.sh trust <repo>"; cmd_trust "$1" ;;
  find) [ $# -eq 1 ] || die 1 "用法：so.sh find <sessionId>"; find_live sessionId "$1" ;;
  byname) [ $# -eq 1 ] || die 1 "用法：so.sh byname <name>"; find_unique name "$1" ;;
  alive)
    [ $# -eq 1 ] || die 1 "用法：so.sh alive <sessionId>"
    if find_live sessionId "$1" >/dev/null; then echo "alive"; else echo "dead"; exit 6; fi ;;
  spawn) cmd_spawn "$@" ;;
  stop) cmd_stop "$@" ;;
  resume) cmd_resume "$@" ;;
  child-cmd) cmd_child_cmd ;;
  console-url) [ $# -le 1 ] || die 1 "用法：so.sh console-url [<網址>]"; cmd_console_url "$@" ;;
  *) die 1 "用法：so.sh {uuid|trust|find|byname|alive|spawn|stop|resume|child-cmd|console-url} ..." ;;
esac
