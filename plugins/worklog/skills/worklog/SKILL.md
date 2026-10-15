---
name: worklog
description: 工作紀錄（worklog）artifact 頁：使用者要把這個 session 的工作、進度、決策記在一個隨時能打開看的頁面，或給了既有工作紀錄網址要接著記。
---

# worklog：session 工作紀錄頁

一個 artifact 頁面，資料放在它的 `db`。頁面只發布一次；之後每有進展就用 `ArtifactData` 寫入，頁面即時更新。範本：`page/worklog.html`（分頁依 `areas` 產生，另有「決策」「時間軸」兩個固定分頁）。

**每輪的完成條件**：回覆使用者之前，這一輪的進展、新決策、答覆都已寫入，`meta/session.focus` 反映現況，該發的通知（見〈通知〉）已發。

## 啟動

**A. 使用者給了既有網址**：`ArtifactData get meta/session` 讀得到就沿用，之後只寫 `db`。

**B. 新開一頁**（`<scratchpad>` 用系統提示裡的 session scratchpad）：
1. 複製並命名，標題取 2–4 個字（例：`Safari 登入 500`）。標題不可含 `/`、`&`、`\`、`<`、`>`：
   ```bash
   sed 's/{{TITLE}}/<標題>/g' ${CLAUDE_SKILL_DIR}/page/worklog.html > <scratchpad>/worklog-<短名>.html
   grep -c '<標題>' <scratchpad>/worklog-<短名>.html   # 要是 2
   ```
2. 載入 `artifact-capabilities` skill（Artifact 工具規定傳 `capabilities` 前要載入），然後直接發布範本：`file_path` 指向該檔、`icon: "list"`、`capabilities: {"db": {}}`、一句 `description`。
3. 一個 `batch` 寫入：`meta/session`（`areas` 依工作性質定 1–4 個分類）＋第一個 `item`＋一則 `log kind:start`。
4. 把網址告訴使用者。

## 資料

只用下表列出的值，頁面只認這些。

| 路徑 | 欄位 |
|--|--|
| `meta/session` | `title`、`session`（session 名或工作目錄）、`focus`（頂端「現在」一行）、`areas: [{key, label, note}]`、`updatedAt` |
| `items/<id>` | `area`（對應 `areas[].key`）、`title`、`summary`、`status`: `active`｜`waiting`｜`blocked`｜`todo`｜`done`、`statusText`、`tasks: [{t, done: true｜false｜"now"}]`、`links: [{label, url}]`、`url`（可選，id 連結）、`updatedAt` |
| `log/<id>` | `at`、`text`（一句話）、`kind`: `start`｜`done`｜`decision`｜`blocker`｜`note`、`ref`（可選，相關 item 或 D 編號） |
| `decisions/D-NNN` | 見〈決策〉 |

- `status`：`waiting`＝卡在使用者（待決定、待授權、待他手動操作）；`blocked`＝卡在外部（服務掛掉、等別人）；`active`＝我方在推進，含等 CI、背景任務、subagent。
- `done: "now"` 標目前這一步，任何 `status` 都可用，同時最多一項。
- `links`、`refs` 的 `url` 用 `https://` 開頭才會變成連結。
- id：`item` 有票號用票號（`PROJ-123`），沒有用短 slug（`dns-cleanup`）；`log` 用 `<yyyymmddHHMMSS>-<2 碼流水>`。
- 時間欄位（`updatedAt`、`at`）用 UTC ISO，例：`2026-10-13T07:20:00Z`，值取自 `date -u +%Y-%m-%dT%H:%M:%SZ` 的輸出。頁面把這些欄位換成檢視者的本地時區顯示。
- 文字欄位（`focus`、`summary`、`statusText`、`tasks[].t`、`log.text`、決策卡各欄）要寫時間點時，寫完整 UTC ISO（`2026-10-14T12:35:00Z`），頁面同樣會換成本地時間。不要寫 `12:35Z`、`20:35` 或 `UTC+8`，頁面不會轉換這些寫法。
- 文字欄位寫短句，一句一件事，只寫有工具輸出佐證的事。金鑰只寫指紋（`sha256` 前 12 碼）。

## 決策

回覆裡出現「要不要／選哪個」（包括順口問「要另外開票嗎？」），**同一輪**就開一張決策卡：

- 欄位：`status: "open"`、`title`、`question`、`context`、`analysis`、`recommendation`、`refs`（字串或 `{label, url}`）、`options: [{key, label, detail, recommended}]`（最多 2 個，標一個 `recommended`）、`updatedAt`。
- 編號：`list decisions` 取最大號 +1。
- 開卡後依〈通知〉發通知。
- 回覆裡附 D 編號、兩個選項、建議哪個，請使用者在頁面按複製鍵貼回。複製鍵產生：
  ```
  【D-NNN】<question>
  回答：<key>｜<label>
  ```
- 使用者貼回後：`status: "answered"`，`answer` 寫完整結論（頁面只顯示 `answer`），加一則 `log kind:decision`，然後照答案執行。

## 何時寫入

| 事件 | 寫什麼 |
|--|--|
| 開始一件新工作 | 新 `item`（`active`）＋`log kind:start` |
| 完成一個步驟 | 該 `item.tasks` 打勾、`statusText`＋`log kind:done` |
| 開決策卡／收到答覆 | 見〈決策〉 |
| 被擋住 | `item.status` 改 `waiting`／`blocked`＋`log kind:blocker`；等決策答覆時只寫 `kind:decision` |
| 順帶發現、這輪不處理 | 新 `item`（`todo`）＋`log kind:note`；開票與否照 repo 規則，需要使用者決定就開決策卡 |
| 需要新分類 | 直接用新的 `area` key（頁面先用 key 當分頁名）；要正式名稱時讀 `meta/session`，在 `areas` 尾端加一筆，整個陣列寫回 |

同一輪的事件合成一個 `batch`，並在同一批更新 `meta/session` 的 `focus`、`updatedAt`。

## 通知

有重要進展或需要決策時，用 `PushNotification` 通知使用者。它是延後載入的工具，第一次用前先執行 `ToolSearch select:PushNotification`。

只在這三種事件發通知：
- 開了決策卡。
- `item.status` 改成 `waiting` 或 `blocked`。
- `item.status` 改成 `done`。

這些事件不發：任務打勾、`log kind:start`、`log kind:note`、一般的 `statusText` 更新。拿不準就不發。

做法：
- 先把 `batch` 寫入完成，再在同一輪發通知。
- 參數：`status: "proactive"`、`message` 一行、200 字以內、不用 markdown、不含金鑰、不放 ISO 時間（要提時間就說相對時間，例：2 小時後）。
- 訊息格式：
  - 決策：`【D-NNN】<question>`
  - 完成：`<item.id> 完成：<statusText>`
  - 等使用者：`<item.id> 等你：<statusText>`
  - 卡在外部：`<item.id> 卡住：<statusText>`
- 工具回覆「not sent」是正常結果（使用者正看著終端機，或通知已關閉）。不要重試。

## 寫入方式

- `ArtifactData` 的 `batch`，`writes[].op` 用 `set`（新建）、`update`（只改傳入的欄位；陣列整個取代）、`delete`。
- 更新既有文件帶 `if_version`（上次讀到或寫入後回傳的版本），新建不帶；版本衝突就重讀再寫。
- 改陣列（`tasks`、`areas`）以目前內容為底改寫：手上有上次寫入的版本與內容就直接用，不確定才先 `get`。
- 寫完跑一次 `query items where status not-in [active, waiting, blocked, todo, done]`，要回 0 筆。
