# worklog

Claude Code skill。把一個 session 的工作、進度、決策記在一個隨時能打開看的 artifact 頁面。

頁面只發布一次。之後每有進展，Claude 就用 `ArtifactData` 寫入頁面的 `db`，頁面即時更新。有重要進展或需要決策時，Claude 會用 `PushNotification` 通知你。

## 前置需求

- 支援 Artifact 發布與 `db` capability 的 Claude Code 帳號。
- 檢視頁面的人需要登入 claude.ai。

`Artifact`、`ArtifactData`、`PushNotification` 與 `artifact-capabilities` skill 都是 Claude Code 內建，不用另外安裝。是否可用取決於帳號的功能開關。

## 安裝

這個 plugin 收在 [zac-skills](../../) marketplace。在 Claude Code 裡執行：

```
/plugin marketplace add im-zac/zac-skills
/plugin install worklog@zac-skills
```

在 shell 裡也可以用 `claude plugin marketplace add im-zac/zac-skills` 和 `claude plugin install worklog@zac-skills`。

更新用 `/plugin update worklog@zac-skills`，移除用 `/plugin uninstall worklog@zac-skills`。

用 plugin 安裝時，skill 的指令名稱是 `/worklog:worklog`。直接對 Claude 說「開一個 worklog」也會觸發。

不想用 plugin 的話，也可以把 `skills/worklog/` 整個資料夾複製到 `~/.claude/skills/worklog/`。

## 使用

- 新開一頁：告訴 Claude「開一個 worklog」。
- 接著記：把既有的 worklog 網址貼給 Claude。

頁面的介面文字是繁體中文。

## 內容

| 檔案 | 用途 |
|--|--|
| `.claude-plugin/` | plugin 的描述檔 |
| `skills/worklog/SKILL.md` | skill 本體：啟動流程、資料格式、決策卡、通知規則、寫入方式 |
| `skills/worklog/page/worklog.html` | artifact 頁面範本，`{{TITLE}}` 會在啟動時換成標題 |

資料格式（`meta/session`、`items/<id>`、`log/<id>`、`decisions/D-NNN`）見 `skills/worklog/SKILL.md` 的〈資料〉。

[`task-orchestrator`](../task-orchestrator/) 用標題引用 `SKILL.md` 的〈資料〉〈決策〉〈何時寫入〉〈通知〉〈寫入方式〉。改這五個標題時，要一起改 task-orchestrator。

## 授權

MIT，見 repo 根目錄的 [`LICENSE`](../../LICENSE)。
