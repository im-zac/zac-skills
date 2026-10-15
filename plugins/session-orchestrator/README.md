# session-orchestrator

Claude Code plugin。用一個 orchestrator session 在 tmux 裡開出、封存（archive）、叫回（resume）、結束其他 Claude Code session，並在一個 artifact 總表看每個 session 在做什麼。

- 開出：對 orchestrator 說「開一個 session 處理 …」，它會用 `claude -w` 在新的 tmux session 裡開一個子 session，並把任務交給它。
- 總表：每個子 session 自己把狀態、背景工作（Monitor、背景 shell、subagent）、PR 連結寫進總表的 `db`。需要你決定、卡住或完成時，子 session 會用 `PushNotification` 通知你。
- 重開機：說「archive all」，每個子 session 會寫交接、停掉背景工作，orchestrator 再結束它們。開機後說「resume all」，orchestrator 用 `claude -r` 把它們叫回來，子 session 照交接重啟背景工作並接著做。

只管理由 orchestrator 開出的 session。工作本身由你在 tmux 裡切進子 session 操作。

## 前置需求

- macOS（`so.sh` 相容內建的 bash 3.2）、tmux、jq、git。
- 支援 Artifact 發布與 `db` capability 的 Claude Code 帳號。檢視總表的人需要登入 claude.ai。
- 要開子 session 的 git repo 已在 Claude Code 接受過資料夾信任：在該 repo 執行一次 `claude` 並接受即可。

`Artifact`、`ArtifactData`、`SendMessage`、`PushNotification` 都是 Claude Code 內建工具，不用另外安裝。是否可用取決於帳號的功能開關。

## 安裝

這個 plugin 收在 [zac-skills](../../) marketplace。在 Claude Code 裡執行：

```
/plugin install session-orchestrator --marketplace im-zac/zac-skills
```

舊版 Claude Code 分兩步：

```
/plugin marketplace add im-zac/zac-skills
/plugin install session-orchestrator@zac-skills
```

plugin 裡有兩個 skill：

| 指令 | 誰用 |
|--|--|
| `/session-orchestrator:session-orchestrator` | 你，在 orchestrator session 裡輸入 |
| `/session-orchestrator:orchestrated-session` | orchestrator 寫進子 session 的第一行 prompt，你不用自己輸入 |

不想用 plugin 的話，把 `skills/` 底下的兩個資料夾複製到 `~/.claude/skills/`。這時指令是 `/session-orchestrator` 與 `/orchestrated-session`，orchestrator 會自動判斷要用哪一種。

## 使用

1. 在 tmux 裡用固定名稱開 orchestrator：`claude -n session-orchestrator`，再輸入 `/session-orchestrator:session-orchestrator`。名稱一定要是 `session-orchestrator`，子 session 只接受這個名稱送來的 `ARCHIVE`。
2. 第一次使用時，orchestrator 會發布總表頁面，並把網址存在 `~/.claude/session-orchestrator/console-url`。之後都沿用同一頁。
3. 用自然語言下指令：
   - 「開一個 session 處理 <任務>」：spawn。repo 不明確時它會問你。
   - 「archive <名稱>」、「resume <名稱>」、「close <名稱>」。
   - 「status」：在終端機印出每個 session 的狀態。
   - 「archive all」：重開機前用，會先列清單請你確認。
4. 重開機後照 orchestrator 給的指令把它叫回來（總表頂端也有這行指令），再說「resume all」。

總表的介面文字是繁體中文。

## 限制

- `so.sh` 讀 `~/.claude/sessions/*.json` 判斷 session 是否還在，讀 `~/.claude.json` 判斷資料夾信任。這兩個是 Claude Code 沒有公開文件的內部格式，Claude Code 更新後可能失效。
- orchestrator 與子 session 的權限模式不同時，`ARCHIVE` 訊息會被擋下等你核准。orchestrator 會提醒你去該 session 核准。
- 子 session 用 `claude -w` 開在 `<repo>/.claude/worktrees/<名稱>`。archive 時會保留 worktree，close 時會先問你才刪。
- 只在 macOS 上測試過。

## 內容

| 檔案 | 用途 |
|--|--|
| `.claude-plugin/` | plugin 的描述檔 |
| `skills/session-orchestrator/SKILL.md` | orchestrator 的流程：啟動、spawn、archive、resume、status、close、決策卡 |
| `skills/session-orchestrator/scripts/so.sh` | 所有 shell 操作：檢查、啟動、等待、結束。退出碼見檔案開頭 |
| `skills/session-orchestrator/page/console.html` | 總表頁面 |
| `skills/orchestrated-session/SKILL.md` | 子 session 的協定：回報欄位、何時寫入、通知、ARCHIVE、resume |
| `tests/` | `so.sh` 的測試與總表頁面的本機預覽 |

## 測試

在 `plugins/session-orchestrator/` 裡執行：

```
bash tests/so_test.sh                                   # so.sh，用假的 claude 與真的 tmux，不花 token
bash tests/preview/make-preview.sh /tmp/preview.html    # 總表頁面的本機預覽與自動檢查
```

## 授權

MIT，見 repo 根目錄的 [`LICENSE`](../../LICENSE)。
