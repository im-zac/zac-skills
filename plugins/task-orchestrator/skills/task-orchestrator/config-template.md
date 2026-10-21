# task-orchestrator 設定

name: my-project

<!--
這是範本。沒有設定檔時，task-orchestrator 會先探勘 repo 與 memory，照這個格式產生草稿給你確認。
也可以手動複製到下面其中一個位置，改成自己專案的值：
- ~/.claude/task-orchestrator/<name>/config.md（個人用，不進 repo）
- <repo>/.claude/task-orchestrator.md（跟 repo 一起 commit，團隊共用）
name 只用英數與 -，交接檔會放在 ~/.claude/task-orchestrator/<name>/handoff.md。
值後面的（來源：…）是探勘留下的出處，重新探勘時用來比對。手寫的值可以不加。
用不到的節可以刪掉，skill 會略過。不要寫 secret、密碼、token。
-->

## 頁面

- 標題：派工主控台
- 分類（`meta/session.areas`）：
  - `impl`｜實作｜改程式並開 PR 的工作。
  - `invest`｜調查｜只查證、不改程式的工作：結論與後續去向。
  - `ops`｜營運操作｜部署、金鑰、環境設定、tracker 狀態這類線上操作。

## Tracker

<!--
留一種，刪掉其他三種。
工作卡 id 只能用英數與 _-.~:@+，不能有 #。
網址樣板裡的 {id} 是整個工作卡 id，{n} 是 id 裡的數字。
-->

### GitHub Issues

- 種類：GitHub Issues
- 工作卡 id：issue `#123` 寫 `GH-123`（regex `^GH-\d+$`）
- 網址樣板：`https://github.com/<owner>/<repo>/issues/{n}`
- 讀寫方式：`gh issue view`、`gh issue comment`、`gh issue edit`
- 狀態對應：開始做＝加 label `in-progress`；完成＝PR merge 後關閉

### Linear

- 種類：Linear（Linear MCP 工具）
- 工作卡 id：`ABC-123`（regex `^ABC-\d+$`，`ABC` 換成 team key）
- 網址樣板：`https://linear.app/<workspace>/issue/{id}`
- 讀寫方式：`get_issue`、`save_issue`（狀態）、`save_comment`
- 狀態對應：照 workspace 的 workflow states

### Jira

- 種類：Jira（Jira MCP 工具或 CLI）
- 工作卡 id：`PROJ-123`（regex `^PROJ-\d+$`，`PROJ` 換成 project key）
- 網址樣板：`https://<site>.atlassian.net/browse/{id}`
- 讀寫方式：（寫用的 MCP 工具或 CLI 指令）
- 狀態對應：照 project 的 workflow

### 沒有 tracker

- 種類：無
- 工作卡 id：一律用 `WORK-<slug>`
- 收尾時不寫 tracker，只更新主控台

## Repo 與 PR

- 程式的基準：`git show origin/main:<path>`
- PR 網址樣板：`https://github.com/<owner>/<repo>/pull/{n}`
- PR 標題慣例：（例：結尾掛票號 `（ABC-123）`；沒有票時加 label）
- 開完 PR 要監看：CI 全部 check
- findings 的處置：逐條回覆；要改的派回原本的 subagent

## 查證來源

- 程式：`git show origin/main:<path>`
- log：（例：Loki、CloudWatch，寫用哪個工具查）
- DB：（例：唯讀帳號，寫連線用的工具或指令）

## 先問才做

- 線上系統：（例：雲端主機、DNS、防火牆、正式環境設定）
- 其他：（例：釘版、發版只走某個 skill）

## 破壞性操作

- 已知的寬限期：（例：某平台刪除服務後 2 小時才真的刪）

## 其他規則

- （團隊流程、票的進出由誰決定、要用的其他 skill。repo 文件已寫清楚的規則，寫「照 <檔案> 的〈標題〉」就好）
