#!/usr/bin/env bash
# 產生本機預覽頁：測試資料＋模擬 db＋console.html＋自動檢查。用法：bash tests/preview/make-preview.sh <輸出路徑>
set -eu
HERE=$(cd "$(dirname "$0")" && pwd -P)
PAGE="$HERE/../../skills/session-orchestrator/page/console.html"
OUT="${1:?用法：make-preview.sh <輸出路徑>}"
{
  echo '<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
  printf '<script>\n%s\n</script>\n' "$(cat "$HERE/fixture.js")"
  printf '<script>\n%s\n</script>\n' "$(cat "$HERE/mock-db.js")"
  echo '</head><body>'
  cat "$PAGE"
  printf '<script>\n%s\n</script>\n' "$(cat "$HERE/assert.js")"
  echo '</body></html>'
} > "$OUT"
echo "$OUT"
