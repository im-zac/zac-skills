# task-orchestrator

Claude Code plugin。讓一個 session 當**派工主控**：查證工作描述、提討論點、派工給 subagent、抽查結果、走 PR，並在一個 artifact 主控台記下每件工作與每個待決策事項。

- 主控台：用 [`worklog`](../worklog/) 的頁面。每次啟動開一頁新的，舊頁封存。
- 交接：結束 session 前，主控把沒做完的事寫進交接檔。下次啟動時，主控把它們帶到新頁。
- 設定檔：專案相關的事寫在設定檔，skill 本身不含任何專案資訊。設定檔寫的是 tracker（GitHub Issues、Linear、Jira 等）、票號格式、repo、查證來源、PR 流程、要先問你才做的線上操作。沒有設定檔時，主控從 repo 與 memory 探勘出草稿給你確認。

## 前置需求

- 已安裝 `worklog` plugin（同一個 marketplace）。task-orchestrator 照 worklog 的〈資料〉〈決策〉〈何時寫入〉〈通知〉〈寫入方式〉寫主控台。
- 支援 Artifact 發布與 `db` capability 的 Claude Code 帳號。檢視主控台的人需要登入 claude.ai。
- tracker 與 PR 用到的工具（例：`gh`、Linear MCP），依你的設定檔而定。

## 安裝

這個 plugin 收在 [zac-skills](../../) marketplace。在 Claude Code 裡執行：

```
/plugin marketplace add im-zac/zac-skills
/plugin install worklog@zac-skills
/plugin install task-orchestrator@zac-skills
```

指令名稱是 `/task-orchestrator:task-orchestrator`。這個 skill 只能由你輸入指令啟動，Claude 不會自己觸發。

## 設定

第一次在一個 repo 啟動時，不用先寫設定檔。主控找不到設定檔時，會先**探勘**：
1. 讀 repo 的 `CLAUDE.md`、`AGENTS.md`、`docs/agents/`、git remote、預設分支、`git log` 的票號格式、`.github/workflows/`、repo 的 `.claude/skills/`、這個專案的 memory，以及目前可用的 MCP 工具。
2. 照範本產生設定檔草稿，每個值都註明來源；推測的值標「推測」。
3. 列出推測的值與〈先問才做〉的每一項，請你確認或修改。〈先問才做〉一定要你確認，探勘只提供線索。
4. 你確認後才寫入設定檔。

設定檔放在下面其中一個位置：
- `~/.claude/task-orchestrator/<name>/config.md`：個人用，不進 repo。探勘預設寫這裡。
- `<repo>/.claude/task-orchestrator.md`：跟 repo 一起 commit，團隊共用。

已經有設定檔時，主控啟動只讀設定檔。repo 慣例改了，告訴主控「重新探勘」，它會列出差異給你確認。也可以手動複製範本 `skills/task-orchestrator/config-template.md` 來寫，範本列了 GitHub Issues、Linear、Jira、沒有 tracker 四種寫法。

`<name>` 是設定檔裡的 `name`。交接檔一律在 `~/.claude/task-orchestrator/<name>/handoff.md`，由主控自己建立與維護。

## 使用

- 個人設定：`/task-orchestrator:task-orchestrator <name>`
- 不帶參數：在 repo 裡輸入 `/task-orchestrator:task-orchestrator`。主控先找 `<repo>/.claude/task-orchestrator.md`，再找 `~/.claude/task-orchestrator/<repo 名稱>/config.md`，都沒有就探勘。
- 指定路徑：`/task-orchestrator:task-orchestrator path/to/config.md`

主控啟動後會發布新的主控台頁面並告訴你網址。決策卡上有複製鍵，按下後把文字貼回 session 就是答覆。要結束 session 時，告訴主控「結束」，它會先寫交接。

主控台的介面文字是繁體中文。

## 內容

| 檔案 | 用途 |
|--|--|
| `.claude-plugin/` | plugin 的描述檔 |
| `skills/task-orchestrator/SKILL.md` | skill 本體：設定檔、探勘、啟動、每件工作的流程、主控台規則、先問才做的動作、交接檔格式 |
| `skills/task-orchestrator/config-template.md` | 設定檔範本 |

## 授權

MIT，見 repo 根目錄的 [`LICENSE`](../../LICENSE)。
