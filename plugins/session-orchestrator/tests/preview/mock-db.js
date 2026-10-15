// 模擬 artifact runtime 的 db：collection(name).onSnapshot 與 doc(path).onSnapshot，資料取自 window.FIXTURE。
window.claude = {
  use: async (cap) => cap !== "db" ? null : {
    collection: (name) => ({
      onSnapshot: (cb) => { const rows = window.FIXTURE[name] || []; cb({ docs: rows.map((r) => ({ id: r.id, data: () => r })) }); return () => {}; }
    }),
    doc: (path) => ({
      onSnapshot: (cb) => { const v = window.FIXTURE[path]; cb({ exists: !!v, data: () => v }); return () => {}; }
    })
  }
};
