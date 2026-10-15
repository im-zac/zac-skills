#!/usr/bin/env bash
# 測試用的假 claude。記下收到的參數與 prompt，寫一筆 registry，收到 TERM 時刪掉並結束。
set -u
args=("$@")
id="" name="" wt="" prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    --session-id|-r) id="$2"; shift 2 ;;
    -n) name="$2"; shift 2 ;;
    -w) wt="$2"; shift 2 ;;
    *) prompt="$1"; shift ;;
  esac
done
printf '%s\n' "${args[@]}" > "$FAKE_LOG_DIR/$name.args"
printf '%s' "$prompt" > "$FAKE_LOG_DIR/$name.prompt"
if [ -n "${FAKE_EXIT:-}" ]; then echo "fake claude: exit early"; exit 1; fi
if [ -n "$wt" ]; then mkdir -p ".claude/worktrees/$wt"; cd ".claude/worktrees/$wt" || exit 1; fi
f="$SO_SESSIONS_DIR/$$.json"
jq -n --argjson pid "$$" --arg ps "$(LC_ALL=C TZ=UTC ps -o lstart= -p $$)" --arg id "$id" --arg name "$name" --arg cwd "$(pwd -P)" \
  '{pid: $pid, procStart: $ps, sessionId: $id, name: $name, cwd: $cwd, status: "idle", statusUpdatedAt: 0}' > "$f"
trap 'rm -f "$f"; exit 0' TERM
while :; do sleep 1 & wait $!; done
