#!/bin/sh
set -eu

db="$HOME/.tutorclip/history.sqlite"

if [ ! -f "$db" ]; then
  echo "History database does not exist yet; schema verification skipped."
  exit 0
fi

schema=$(sqlite3 "$db" ".schema sessions" 2>/dev/null || true)
if [ -z "$schema" ]; then
  echo "History sessions table does not exist yet; schema verification skipped."
  exit 0
fi

echo "$schema" | rg -i "screenshot|image|png|jpeg|jpg|heic|tiff|blob" && {
  echo "History schema contains screenshot-like storage."
  exit 1
}

content=$(sqlite3 "$db" "SELECT coalesce(selected_answer, '') || char(10) || coalesce(correct_answer, '') || char(10) || coalesce(vocabulary_json, '') || char(10) || ocr_json || char(10) || messages_json FROM sessions;" 2>/dev/null || true)
if [ -n "$content" ]; then
  echo "$content" | rg -i "screenshotInMemory|data:image/|pngData|jpegData|NSImage|CGImage|base64" && {
    echo "History content contains screenshot-like payload markers."
    exit 1
  }
fi

echo "History schema verification passed."
