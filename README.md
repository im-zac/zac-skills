# zac-skills

im-zac 的 Claude Code plugins。這個 repo 是一個 plugin marketplace。

| plugin | 用途 |
|--|--|
| [`worklog`](plugins/worklog/) | 把一個 session 的工作、進度、決策記在一個隨時能打開看的 artifact 頁面；有重要進展或需要決策時推播通知。 |
| [`session-orchestrator`](plugins/session-orchestrator/) | 用一個 orchestrator session 在 tmux 裡開出、archive、resume、close 其他 Claude Code session，並在 artifact 總表看每個 session 的狀態。 |

## 安裝

在 Claude Code 裡加入 marketplace，再安裝要用的 plugin：

```
/plugin marketplace add im-zac/zac-skills
/plugin install worklog@zac-skills
/plugin install session-orchestrator@zac-skills
```

更新用 `/plugin marketplace update zac-skills`。各 plugin 的前置需求與用法見各自的 README。

## 授權

MIT，見 `LICENSE`。
