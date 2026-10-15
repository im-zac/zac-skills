// 預覽用的測試資料。時間以載入當下為準，才能測「最後回報 N 分鐘前」與標黃。
(function () {
  const ago = (min) => new Date(Date.now() - min * 60000).toISOString();
  const repo = "/Users/me/dev/shop";
  const wt = repo + "/.claude/worktrees/";
  const s = (id, lifecycle, task, spawnMin, archivedMin) => ({
    id, sessionId: "aaaaaaaa-0000-0000-0000-" + String(id.length).padStart(12, "0"), repo, cwd: wt + id, tmux: id,
    task, lifecycle, spawnedAt: ago(spawnMin), archivedAt: archivedMin == null ? undefined : ago(archivedMin)
  });
  window.FIXTURE = {
    "meta/orchestrator": { focus: "等 tai-1302 決定要不要合併", sessionId: "11111111-2222-3333-4444-555555555555", cwd: "/Users/me/dev/session-orchestrator", updatedAt: ago(2) },
    sessions: [
      s("tai-1302", "running", "修 TAI-1302 的下單逾時", 120),
      s("weekly", "running", "產出本週週報", 300),
      s("fresh", "running", "剛開、還沒回報的 session", 1),
      s("blocker", "running", "部署到 Zeabur", 90),
      s("data-fetcher", "archived", "補抓 9 月資料", 5000, 60),
      s("old-probe", "lost", "測試用", 9000, 30),
      s("done-task", "closed", "已完成的任務", 9000, 600)
    ],
    reports: [
      { id: "tai-1302", status: "waiting", focus: "等你決定要不要合併 PR #812", statusText: "CI 全綠，review 0 findings",
        background: [{ kind: "monitor", label: "gh pr checks 812", restart: "Monitor：gh pr checks 812 --watch" },
                     { kind: "subagent", label: "補測試", restart: "重新派 subagent 補 order-timeout 測試" }],
        links: [{ label: "PR #812", url: "https://github.com/example/repo/pull/812" }], lastReportAt: ago(3) },
      { id: "weekly", status: "active", focus: "整理 Loki 錯誤統計", statusText: "已完成 3/5 段",
        background: [{ kind: "loop", label: "/loop 20m 檢查資料", restart: "/loop 20m 檢查資料" }], links: [], lastReportAt: ago(45) },
      { id: "blocker", status: "blocked", focus: "Zeabur API 回 503", statusText: "2026-10-14T08:00:00Z 起無法部署", background: [], links: [], lastReportAt: ago(10) },
      { id: "data-fetcher", status: "active", focus: "補抓 9 月資料", statusText: "抓到 9/18", background: [], links: [], lastReportAt: ago(61),
        handoff: { writtenAt: ago(61), now: "9/1–9/18 已補齊", next: "從 9/19 繼續抓",
                   restart: [{ kind: "shell", label: "bun run fetch --from 2026-09-19", restart: "Bash 背景執行 bun run fetch --from 2026-09-19" }] } },
      { id: "old-probe", status: "active", focus: "測試用", lastReportAt: ago(40) }
    ],
    decisions: [
      { id: "D-001", status: "open", title: "archive 閒置的 weekly", question: "weekly 已 45 分鐘沒有回報，要 archive 嗎？",
        context: "weekly 狀態是進行中，但最後回報在 45 分鐘前。", recommendation: "先切進去看，再決定。",
        options: [{ key: "A", label: "archive", detail: "寫交接後結束 process", recommended: true }, { key: "B", label: "保留", detail: "繼續等它回報" }],
        updatedAt: ago(5) }
    ],
    log: [
      { id: "20261014070000-01", at: ago(120), text: "spawn tai-1302", kind: "start", ref: "tai-1302" },
      { id: "20261014080000-01", at: ago(60), text: "archive data-fetcher", kind: "done", ref: "data-fetcher" },
      { id: "20261014083000-01", at: ago(30), text: "old-probe 的 process 不在，標成 lost", kind: "blocker", ref: "old-probe" }
    ]
  };
})();
