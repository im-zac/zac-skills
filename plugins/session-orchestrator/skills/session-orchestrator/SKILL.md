---
name: session-orchestrator
description: Session 總管：spawn、archive、resume、close 由本 session 開出的 Claude Code 子 session，並維護 session 總表。
disable-model-invocation: true
---

# session-orchestrator：子 session 總管

本 session 是 **orchestrator**，只管子 session 的 **lifecycle**：開出（spawn）、封存（archive）、叫回（resume）、結束（close）。子 session 的工作與通知由子 session 和使用者直接處理，使用者用 `tmux attach` 切進去操作。

- shell 操作一律用 `bash ${CLAUDE_SKILL_DIR}/scripts/so.sh <子指令>`，下文簡寫成 `so.sh`。
- **總表**：一個 artifact 頁面（原始檔 `page/console.html`），資料放在它的 `db`。網址是 `so.sh console-url` 的輸出，下文寫成 `<總表網址>`；`ArtifactData` 的 `url` 都用它。
- 管理範圍是 `db` 的 `sessions/` 裡有的 session。
- 時間一律用 `date -u +%Y-%m-%dT%H:%M:%SZ` 的輸出。

**每輪的完成條件**：回覆使用者之前，這一輪的每個 lifecycle 變化都已寫進 `sessions/<name>` 與 `log`，`meta/orchestrator.focus` 反映現況。

## 啟動

每次載入本 skill（包括 resume 本 session 之後）：
1. 執行 `ToolSearch select:ArtifactData,SendMessage,PushNotification,ListAgents`。
2. `so.sh console-url`。回 6 表示還沒有總表，先發布一個：
   1. 載入 `artifact-capabilities` skill（Artifact 工具規定傳 `capabilities` 前要載入）。
   2. 發布 `${CLAUDE_SKILL_DIR}/page/console.html`：`icon: "terminal"`、`capabilities: {"db": {}}`、一句 `description`。
   3. `so.sh console-url <發布結果的網址>`，存下網址。
3. 用 `ListAgents` 讀第一行 `This session is <名稱>`。名稱要是 `session-orchestrator`，子 session 才接受它送的 `ARCHIVE`。名稱不同時，停下來請使用者輸入 `/rename session-orchestrator`；這個指令不能用時，請使用者退出後用 `claude -r <本 session id> -n session-orchestrator` 重開。
4. `so.sh byname session-orchestrator`，取得本 session 的 `sessionId`、`cwd`。回 8 表示有兩個以上同名的 session 在執行：把 stderr 給使用者，請使用者關掉不是本 session 的那個，再重做這一步。
5. `meta/orchestrator` 寫入 `sessionId`、`cwd`、`focus`、`updatedAt`（文件不存在用 `set`，存在用 `update`）。
6. 執行〈status〉。

## 指令

使用者用自然語言下指令，下列每節是一個指令。

### spawn

1. 決定 `<name>`：使用者給的名稱，或從任務取（票號轉小寫，例：`tai-1302`）。只用小寫英數與 `-`。
2. 決定 `repo`，依序：
   1. 依任務內容判斷：使用者提到的 repo 名稱或路徑、票號所屬的專案。
   2. 參考 `sessions/` 裡其他 session 的 `repo`。
   3. 仍不確定就問使用者。
3. `ArtifactData get sessions/<name>`。文件已存在就請使用者換名稱。
4. 用 Write 工具把 start prompt 寫進 `<scratchpad>/spawn-<name>.txt`（shell 的 heredoc 會展開 `$` 與反引號）。`<子 skill 指令>` 是 `so.sh child-cmd` 的輸出：
   ```
   <子 skill 指令> start <總表網址> session-orchestrator <name>
   <任務說明>
   ```
   任務說明要讓子 session 不必回頭問就能開工：使用者的原話、相關票號與連結、完成條件。只寫使用者給的與查得到的事實。
5. 執行 `so.sh spawn <name> <repo> <scratchpad>/spawn-<name>.txt`。

   | 退出碼 | 意思 | 處理 |
   |--|--|--|
   | 0 | 成功，stdout 是 JSON：`pid`、`sessionId`、`name`、`cwd`、`repo`、`tmux` | 繼續第 6 步 |
   | 1 | 參數錯誤 | 依 stderr 改正後重試 |
   | 2 | repo 還沒接受資料夾信任 | 請使用者在該 repo 執行一次 `claude` 並接受信任，再重試 |
   | 3 | 同名 tmux session 已存在 | 請使用者換名稱 |
   | 4 | 30 秒內 registry 沒出現 | 把 stderr（含 uuid 與 pane 最後幾行）給使用者，問使用者要不要用 `so.sh stop <uuid> <name>` 清掉 |
   | 5 | repo 目錄不存在 | 問使用者 |

6. 一個 `batch`：
   - `set sessions/<name>`：`sessionId`、`repo`、`cwd`、`tmux`（取 JSON 裡的值）、`task`（任務一句話摘要）、`lifecycle: "running"`、`spawnedAt`。
   - `set log/<id>`：`kind: "start"`、`text: "spawn <name>"`、`ref: "<name>"`。
   - `update meta/orchestrator`：`focus`、`updatedAt`。
7. 回覆使用者：名稱、`cwd`、切換指令 `tmux attach -t <name>`。

### archive

1. `ArtifactData get sessions/<name>`，確認 `lifecycle` 是 `running`。
2. `so.sh alive <sessionId>`。回 `dead` 時跳到第 7 步，`lifecycle` 寫 `lost`。
3. `update sessions/<name>`：`archiveRequestedAt` 寫現在時間。
4. `SendMessage`：`to: "<name>"`、`message: "ARCHIVE"`、`notify_when_idle: true`。
   - 回覆說名稱有歧義：改用 `ListAgents` 裡該 session 的 `[ref]` 重送。
   - 收到 `[Cross-session delivery notice]` 說訊息被擋下等待核准：子 session 的權限模式和本 session 不同。請使用者到該 session 核准，核准後再等 idle 通知。
5. 告訴使用者「已請 <name> 寫交接，等它完成」，然後**結束這一輪**。idle 通知要等本 session 這一輪結束後才會送到。
6. 收到 `<name>` 的 idle 通知後：
   1. `ArtifactData get reports/<name>`。
   2. **交接**完成的條件：`handoff.writtenAt` 不早於 `sessions/<name>.archiveRequestedAt`（兩者都只到秒，可能相同）。比它早的是上一次 archive 留下的交接。
   3. 交接沒有完成，或通知說訂閱過期：開決策卡（A 再送一次 `ARCHIVE`；B 強制結束並標 `lost`），process 保持執行。
7. `so.sh stop <sessionId> <name>`。回 4（pid 10 秒沒結束）時告訴使用者，`lifecycle` 維持原值。
8. 一個 `batch`：
   - `update sessions/<name>`：`lifecycle: "archived"`（第 2 步回 dead 時寫 `"lost"`）、`archivedAt`。
   - `set log/<id>`：`kind: "done"`、`text: "archive <name>"`。lost 時改成 `kind: "blocker"`、`text: "<name> 的 process 不在，標成 lost"`。
   - `update meta/orchestrator`：`focus`、`updatedAt`。

worktree 一律保留，resume 要用它。

### resume

1. `ArtifactData get sessions/<name>`，確認 `lifecycle` 是 `archived` 或 `lost`。
2. 用 Write 工具把 resume prompt 寫進 `<scratchpad>/resume-<name>.txt`：
   ```
   <子 skill 指令> resume <總表網址> session-orchestrator <name>
   ```
3. 執行 `so.sh resume <name> <sessionId> <cwd> <scratchpad>/resume-<name>.txt`。

   | 退出碼 | 意思 | 處理 |
   |--|--|--|
   | 0 | 成功 | 繼續第 4 步 |
   | 3 | 同名 tmux session 已存在 | 問使用者要不要先關掉它 |
   | 4 | 30 秒內 registry 沒出現 | 把 stderr 給使用者 |
   | 5 | `cwd` 不存在（worktree 被刪了） | 問使用者 |
   | 7 | session 其實還在執行 | `lifecycle` 改回 `running`，告訴使用者 |

4. 一個 `batch`：`update sessions/<name>`（`lifecycle: "running"`、`resumedAt`）＋`log`（`kind: "start"`、`text: "resume <name>"`）＋`update meta/orchestrator`。

### archive all

1. 列出 `lifecycle` 是 `running` 的 session，請使用者確認一次。
2. 對每個 session 做〈archive〉第 2–4 步。全部送出後才結束這一輪。
3. 每收到一則 idle 通知，就對那個 session 做〈archive〉第 6–8 步。
4. 全部完成後告訴使用者：可以關機了。開機後執行 `cd '<本 session cwd>' && claude -r <本 session id> -n session-orchestrator`，再說「resume all」。

### resume all

1. 對每個 `lifecycle` 是 `archived` 的 session 執行〈resume〉。
2. `lost` 的 session 先列出來，問使用者要不要也 resume。

### status

1. `ArtifactData list sessions` 與 `list reports`。
2. 對每個 `lifecycle` 是 `running` 的 session 執行 `so.sh alive <sessionId>`。回 `dead` 的改成 `lost`（一個 `batch`：`sessions/<name>`＋`log kind: "blocker"`）。
3. 在終端機印一張表：名稱｜lifecycle｜status｜focus｜最後回報（相對時間）。

存活只在這裡、以及 archive 第 2 步檢查。

### close

1. `lifecycle` 是 `running` 時，先做〈archive〉。
2. `update sessions/<name>`：`lifecycle: "closed"`＋一則 `log`。
3. `cwd` 在 `<repo>/.claude/worktrees/` 底下時，問使用者要不要刪 worktree。使用者答要，才執行：
   1. `git -C <repo> worktree unlock <cwd>`。`claude -w` 會鎖住 worktree，process 結束後鎖還在。回報 `is not locked` 時略過這一步。
   2. `git -C <repo> worktree remove <cwd>`。git 回報有未 commit 或未追蹤的檔案時，把清單給使用者，使用者確認後才加 `--force`。

## 資料

| 路徑 | 欄位 |
|--|--|
| `meta/orchestrator` | `focus`、`sessionId`、`cwd`、`updatedAt` |
| `sessions/<name>` | `sessionId`、`repo`、`cwd`、`tmux`、`task`、`lifecycle`: `running`｜`archived`｜`lost`｜`closed`、`spawnedAt`、`archiveRequestedAt`、`archivedAt`、`resumedAt` |
| `reports/<name>` | 子 session 寫，orchestrator 只讀 |
| `decisions/D-NNN` | 見〈決策〉 |
| `log/<id>` | `at`、`text`（一句話）、`kind`: `start`｜`done`｜`decision`｜`blocker`｜`note`、`ref`（session 名稱或 D 編號） |

## 寫入方式

- `ArtifactData` 的 `batch`，`writes[].op` 用 `set`（新建）或 `update`（只改傳入的欄位，陣列整個取代）。
- 更新既有文件帶 `if_version`（上次讀到或寫入後回傳的版本）。版本衝突就重讀再寫。
- `log` 的 id 用 `<yyyymmddHHMMSS>-<2 碼流水>`（UTC）。每則 `log` 都要有 `at`（寫入時間），頁面用它排序與分日期。

## 決策

回覆裡出現「要不要／選哪個」時，同一輪開一張決策卡：
1. 欄位：`status: "open"`、`title`、`question`、`context`、`recommendation`、`refs`、`options: [{key, label, detail, recommended}]`（最多 2 個，標一個 `recommended`）、`updatedAt`。編號用 `list decisions` 取最大號 +1。
2. 寫入後發 `PushNotification`：`status: "proactive"`、`message: "【D-NNN】<question>"`。回覆「not sent」時就此結束。
3. 回覆裡附 D 編號、兩個選項、建議哪個，請使用者在頁面按「複製回答」貼回。
4. 使用者貼回後：`status: "answered"`、`answer` 寫完整結論，加一則 `log kind: "decision"`，然後照答案執行。

## 先問使用者才做的動作

- `archive all`（列清單確認一次）。
- 刪 worktree。
- 關掉不在 `sessions/` 裡的 tmux session。

單一 session 的 spawn、archive、resume、close 是使用者明確下的指令，直接做。
