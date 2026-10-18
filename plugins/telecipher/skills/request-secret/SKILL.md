---
name: request-secret
description: 需要使用者提供 token、API key、密碼、憑證檔等敏感資料時使用。向 telecipher 登錄需求，使用者在 telecipher 頁面填值，值直接寫進目標檔，不經過這個對話。絕不要請使用者把 secret 貼進終端機。
---

# request-secret：向 telecipher 要 secret

值不會經過你。你只知道「需求已登錄」與「已寫入」。

## 流程

1. 決定寫法：
   - 單一 key（API token、密碼）→ `--mode env --key KEY --path <專案>/.env`。
   - 整個檔（service account JSON、私鑰）→ `--mode file --path <絕對路徑>`。目標不能已存在。
   - 路徑必須在使用者 home 內。`~/.ssh`、`~/Library`、shell rc、`~/.claude/settings*` 會被拒絕。
2. 用 Bash 的 `run_in_background: true` 執行（前景 Bash 有 10 分鐘上限，使用者可能一小時後才填）：
   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/request.sh --path ~/dev/app/.env --mode env --key OPENAI_API_KEY --description "OpenAI API key，給 app 的 LLM 呼叫用"
   ```
   `--description` 一句話說明用途，1–500 字。`--session` 預設取 tmux session 名，可覆寫。`--wait-minutes` 預設 120。
3. 立刻告訴使用者：「已向 telecipher 登錄需求，請到 telecipher 填 OPENAI_API_KEY（寫入 ~/dev/app/.env）」。繼續做不依賴這個值的工作。
4. 背景任務結束時看 stdout 最後一行與 exit code：
   - `FULFILLED <id>`（exit 0）→ 值已在目標檔，繼續。
   - `CANCELLED <id>`（exit 5）→ 使用者取消了，問使用者下一步。
   - `TIMEOUT <id>`（exit 6）→ 告訴使用者需求還在 telecipher 待處理，可再跑一次等待。
   - exit 2／3／4 → 把 stderr 的訊息告訴使用者（缺 token、路徑被拒、telecipher 未啟動）。

## 禁止

- 完成後**不要**用 `cat`、`Read`、`echo $KEY`、`grep` 或任何方式讀目標檔的內容。要用值就讓程式在 runtime 讀檔或讀 env。
- 不要把值寫進 log、commit、對話。
- 不要替使用者猜值或放 placeholder 進目標檔。
