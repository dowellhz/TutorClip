#!/bin/sh
set -eu

diagnostics_file="${1:-$HOME/.tutorclip/diagnostics.txt}"

if [ ! -f "$diagnostics_file" ]; then
  echo "Runtime diagnostics file does not exist: $diagnostics_file"
  exit 1
fi

require_pass() {
  label="$1"
  pattern="$2"
  if ! rg -q "$pattern" "$diagnostics_file"; then
    echo "Runtime diagnostic did not pass: $label"
    cat "$diagnostics_file"
    exit 1
  fi
}

if rg -n "=(FAIL|WARN)\\b" "$diagnostics_file"; then
  echo "Runtime diagnostics contain FAIL or WARN."
  cat "$diagnostics_file"
  exit 1
fi

require_pass "Runtime identity" "^Runtime=bundle=.*/TutorClip\\.app .*signing=.*team=T84BKD53ZD"
require_pass "Screen Recording" "^(屏幕录制|Screen Recording)=PASS\\b"
require_pass "Capture Probe" "^(实际截屏|Capture Probe)=PASS\\b"
require_pass "Global Shortcut" "^(全局快捷键|Global Shortcut)=PASS .*Shift \\+ Command \\+ O"
require_pass "Screenshot Persistence" "^(截图持久化|Screenshot Persistence)=PASS\\b"

echo "Runtime diagnostics verification passed."
