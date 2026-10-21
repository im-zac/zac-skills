---
name: task-orchestrator
description: 派工主控 session：查證、派工、抽查、走 PR，並在 worklog 頁面維護派工主控台。
disable-model-invocation: true
---

# task-orchestrator：派工主控

參數：`<設定名>` 或設定檔路徑（見〈設定檔〉）。

本 session 是**主控**：查證、提討論點、派工給 subagent、抽查、走 PR、更新 tracker 與主控台。實作交給 subagent，主控負責判斷與驗收。

專案相關的事（tracker、票號、repo、查證來源、PR 流程、要先問的線上操作）都寫在設定檔。本檔寫「照設定檔的〈X〉」的地方，就去讀設定檔的那一節。

**每輪的完成條件**：回覆使用者之前，這一輪做過的每件工作都有工作卡（有沒有 tracker 票都算），決策卡與 `meta/session.focus` 都已寫入主控台，tracker 狀態與實際一致（設定檔的 tracker 是「無」時略過這項）。

## 設定檔

依序找第一個存在的檔案：
1. 參數是 `.md` 結尾的路徑：用該檔。
2. 參數是設定名：`~/.claude/task-orchestrator/<設定名>/config.md`。
3. 沒有參數：目前 repo 的 `.claude/task-orchestrator.md`。
4. 沒有參數：`~/.claude/task-orchestrator/<repo 名稱>/config.md`。`<repo 名稱>` 取 `git remote get-url origin` 的最後一段，去掉 `.git`。

都找不到時，照〈探勘〉產生一份。使用者說「重新探勘」時，也照〈探勘〉做，並列出與現有設定的差異。已有設定檔時，啟動只讀設定檔，不探勘。

設定檔不寫 secret、密碼、token。連線方式寫工具名稱或指令。

交接檔固定在 `~/.claude/task-orchestrator/<name>/handoff.md`，`<name>` 是設定檔裡的 `name`。交接檔是執行狀態，不放進 repo。

## 探勘

從目前的 repo 與 memory 找出這個專案的 tracker 與 repo 慣例，寫成設定檔草稿，經使用者確認後才寫入。

1. 讀下表的來源。讀不到的來源略過。

   | 要找的值 | 來源 |
   |--|--|
   | tracker 種類、讀寫方式 | `CLAUDE.md`、`AGENTS.md`、`docs/agents/`、`CONTRIBUTING.md` 提到的 tracker；可用的 MCP 工具（用 ToolSearch 搜 `linear`、`jira`、`github`） |
   | 票號格式 | `git log origin/<預設分支> --oneline -200` 裡最常見的 `[A-Z]+-\d+` 或 `#\d+`；文件裡的 PR 標題慣例 |
   | 程式的基準 | `git symbolic-ref refs/remotes/origin/HEAD` |
   | repo、PR 網址樣板 | `git remote get-url origin` |
   | PR 後要監看的 check | `.github/workflows/`；最近一個 merged PR 的 `gh pr checks` |
   | PR 流程、findings 的處置 | `CLAUDE.md`、`.github/pull_request_template.md`、repo 的 `.claude/skills/` |
   | 查證來源 | 可用的 MCP 工具（log、metrics、DB）；文件提到的觀測工具 |
   | 先問才做的線索 | 文件與 skills 提到的部署、雲端服務、DNS、正式環境 |
   | 團隊規則 | 這個專案的 memory：系統提示列出的 memory 目錄裡的 `MEMORY.md`，與它指向的檔案 |

2. 照 `${CLAUDE_SKILL_DIR}/config-template.md` 的格式，把草稿寫到 session scratchpad。
   - 每個值後面註明來源，例：`（來源：CLAUDE.md:248）`、`（來源：git log）`。
   - 推得出來但沒有直接證據的值，標 `（推測）`。
   - repo 文件已經寫清楚的長規則，只寫指向（檔案與標題），不抄內容。
3. 〈先問才做〉的每一項都標 `（待確認）`。探勘只能列線索，漏列一項就可能沒問使用者就動到正式環境。
4. 在對話裡列出所有 `（推測）` 與 `（待確認）` 的值，請使用者逐項確認或修改。
5. 使用者確認後，拿掉 `（推測）` 與 `（待確認）` 標記，保留來源註記，寫入設定檔：
   - 預設寫到 `~/.claude/task-orchestrator/<name>/config.md`。`name` 預設用 repo 名稱（同〈設定檔〉第 4 項），之後不帶參數啟動也找得到。
   - 使用者要團隊共用時，寫到 `<repo>/.claude/task-orchestrator.md`。這是 repo 變更，照 repo 的流程 commit。

重新探勘時，第 4 步改成列出新草稿與現有設定的差異，使用者確認每一項差異後才改寫。

## 啟動

1. 讀設定檔。讀交接檔；不存在就照〈交接檔格式〉建一份空的。
2. 用 Skill 工具載入 `worklog:worklog`。照它的〈啟動〉B 開一個新頁：標題用設定檔〈頁面〉的標題，`meta/session.areas` 用設定檔〈頁面〉的分類。每次啟動都開新頁（分段工作，舊頁封存不再寫）。
3. 把交接檔「帶到新主控台」的每一項建成新頁的工作卡或決策卡。寫之前先對 tracker 查證現況。
4. 更新交接檔：新頁網址寫進「現役主控台」，原本的現役網址移到「已封存」，清掉已帶過去的項目。

使用者說要結束 session 時，把還沒完成的事項（含未答的決策卡）寫進交接檔的「帶到新主控台」，下一個 session 才接得上。

## 每件工作的流程

1. **查證**：工作描述裡每個事實主張，都照設定檔的〈查證來源〉對過，各標成符合／不符／查不到。
2. **提討論點**：不符、有風險、要取捨的點開決策卡，等使用者答覆再動手。
3. **派工**：實作派 `isolation: "worktree"` subagent；調查派唯讀 subagent。讀 secret 的 prompt 寫明指紋寫法（`sha256` 前 12 碼），禁用 `${K:-…}`（它會印出明文）。
4. **抽查**：subagent 的每個結論都自己重跑關鍵指令或讀 diff 確認過，才算完成。
5. **PR**：照設定檔的〈Repo 與 PR〉開 PR、監看 check、逐條處置 findings。
6. **收尾**：tracker 狀態與 comment、主控台工作卡；有跨 session 的教訓才寫 memory。

## 主控台

主控台就是 worklog 頁面。工作卡、時間軸、決策卡、通知、寫入方式、時間格式、自查，全部照 `worklog` skill 的〈資料〉〈決策〉〈何時寫入〉〈通知〉〈寫入方式〉。主控台另外有以下規則：

| 項目 | 主控台的寫法 |
|--|--|
| 工作卡 id | tracker 票號（格式照設定檔〈Tracker〉）。id 只能用英數與 `_-.~:@+`。沒有票的工作（寫文件、臨時調查、改設定）用 `WORK-<slug>`，同樣要建卡 |
| `url` | 有票號時，照設定檔〈Tracker〉的網址樣板產生 |
| `links` | PR 寫 `{label: "#N", url}`；延伸出去的票寫 `{label: <票號>, url}`，只放已存在的票。網址照設定檔的樣板產生 |
| `area` | 用設定檔〈頁面〉列的分類 key |
| 決策卡 `refs` | 票號與 PR 寫成 `{label, url}`，待決的延伸問題放這裡 |

範圍外的新發現（取代 worklog〈何時寫入〉的「順帶發現」那一列）：只開決策卡問使用者要不要開票，不建工作卡。使用者答開、票號出來後才建卡。

tracker comment 寫在狀態有實質變化時（完成一段、被擋、收尾），不是每個步驟都寫。

## 先問使用者才做的動作

- 開 PR、merge（使用者當輪已明示則直接做）。
- 線上變更：設定檔〈先問才做〉列的系統。唯讀查詢直接做。
- 刪除外部資源。
- 設定檔〈先問才做〉另外列的動作。

破壞性操作的順序：
1. 唯讀盤點目標與它的依賴。
2. 對還在用的依賴建 smoke test 基準。
3. 問使用者，把盤點的新發現寫進問題。
4. 逐步執行，每步後重跑 smoke test。
5. 查有無寬限期（設定檔〈破壞性操作〉列了已知的例子），排背景驗證到寬限期之後。

## 交接檔格式

```markdown
# 主控台交接

## 現役主控台

- 網址：<url>（<UTC ISO 起始時間>起）

## 已封存（不再寫入；要查舊紀錄用 ArtifactData 讀）

- <url>（<起>～<迄>）

## 帶到新主控台

- <票號或 WORK-slug>：<現況一句話>，<下一步>
- 決策卡 D-NNN：<question>（未答）

## 不用帶（別的 session 或別人在追）

- <票號>：<誰在追>
```
