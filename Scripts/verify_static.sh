#!/bin/sh
set -eu

max_lines=500
warn_lines=450
failed=0
app_name="TutorClip"
xcode_app_dir=".xcode-derived/Build/Products/Debug/${app_name}.app"

echo "Checking Swift source file lengths..."
for file in $(find Sources Tests -type f -name '*.swift' | sort); do
  lines=$(wc -l < "$file" | tr -d ' ')
  if [ "$lines" -gt "$max_lines" ]; then
    echo "File exceeds ${max_lines} lines: $file ($lines)"
    failed=1
  elif [ "$lines" -ge "$warn_lines" ]; then
    echo "File is approaching ${max_lines} lines; split before adding behavior: $file ($lines)"
    failed=1
  fi
done

echo "Checking Swift files are included in the Xcode project..."
for swift_file in $(find Sources/TutorClip -maxdepth 1 -name '*.swift' | sort); do
  name=$(basename "$swift_file")
  if ! rg -q "$name" TutorClip.xcodeproj/project.pbxproj; then
    echo "Swift file is not included in TutorClip.xcodeproj: $swift_file"
    failed=1
  fi
done

echo "Checking for obvious secret patterns..."
if rg -n "sk-[A-Za-z0-9_-]{20,}|deepseekApiKey\"\\s*:\\s*\"(?!your-api-key)|api[_-]?key\\s*=\\s*['\\\"][A-Za-z0-9_-]{20,}" \
  Sources README.md AGENTS.md VERIFY.md Makefile Scripts 2>/dev/null; then
  echo "Potential secret found."
  failed=1
fi

echo "Checking verbose text logging is debug-only..."
if ! sed -n '/private static var verboseTextLoggingEnabled/,/^    }/p' Sources/TutorClip/TutorClipApp.swift \
  | rg -U '#if DEBUG[\s\S]*TUTORCLIP_VERBOSE_TEXT_LOGS[\s\S]*#else[\s\S]*false[\s\S]*#endif' >/dev/null; then
  echo "Full OCR/chat text logging must be unavailable in release builds."
  failed=1
fi

echo "Checking privacy-sensitive API usage..."
if rg -n "SecItem|kSecClass|CGWindowListCreateImage|NSBitmapImageRep|write\\(to:.*screenshot|pngData|jpegData|representation\\(using:\\s*\\.(png|jpeg)" Sources/TutorClip Scripts/verify_ocr.swift 2>/dev/null; then
  echo "Potential privacy or deprecated capture issue found."
  failed=1
fi

echo "Checking permission request routing..."
if rg -n -e "--request-permissions" Makefile README.md VERIFY.md Sources/TutorClip Scripts \
  -g '!verify_static.sh' 2>/dev/null; then
  echo "Permission requests must be routed through the app launch marker, not CLI arguments."
  failed=1
fi

echo "Checking OCR formatting and question rendering ownership..."
if [ -e Sources/TutorClip/OCRInitialTextFormatter.swift ]; then
  echo "Local OCR formatter must not be reintroduced; use DeepSeek formatting plus Markdown rendering."
  failed=1
fi
if ! rg -n "RecognizeDocumentsRequest" Sources/TutorClip/OCRService.swift >/dev/null 2>&1 \
  || ! rg -n "catch is CancellationError" Sources/TutorClip/OCRService.swift >/dev/null 2>&1 \
  || ! rg -n "task\?\.cancel\(\)" Sources/TutorClip/OCRRequestLifecycle.swift >/dev/null 2>&1 \
  || ! rg -n "!Task\.isCancelled" Sources/TutorClip/OCRRequestLifecycle.swift >/dev/null 2>&1; then
  echo "Modern Vision OCR must be owned by a cancellable task and reject cancelled results."
  failed=1
fi
if ! rg -n "window\.isReleasedWhenClosed = false" Sources/TutorClip/ScreenCaptureHealthService.swift >/dev/null 2>&1; then
  echo "The strongly owned capture-probe window must disable AppKit auto-release."
  failed=1
fi
if ! rg -n "NSMutableAttributedString\\(" Sources/TutorClip/SelectableMarkdownTextView.swift >/dev/null 2>&1; then
  echo "Question text renderer should use system Markdown parsing instead of local formatting heuristics."
  failed=1
fi

echo "Checking docs for obsolete UI actions..."
if rg -n "Combined mode|Check OCR|Selected-text actions: Translate, Explain, Vocabulary, Grammar|OCR coordinate overlay|Selectable OCR text layer" README.md VERIFY.md AGENTS.md 2>/dev/null; then
  echo "Docs mention obsolete TutorClip UI/actions."
  failed=1
fi

echo "Checking local TutorClip data for screenshots..."
if [ -d "$HOME/.tutorclip" ]; then
  if find "$HOME/.tutorclip" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.heic' -o -iname '*.tiff' \) | grep .; then
    echo "Screenshot-like files found in ~/.tutorclip."
    failed=1
  fi
fi

echo "Checking history schema..."
./Scripts/verify_history_schema.sh

./Scripts/verify_payload_privacy.sh

echo "Building..."
make xcode-build-signed

echo "Running XCTest suite..."
make test

echo "Verifying Markdown pipeline..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-markdown-pipeline

echo "Verifying selected-text prompts..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-selection-prompts

echo "Verifying notes question formatting..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-notes-question-formatting

echo "Verifying OCR formatting state messages..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-ocr-format-state

echo "Verifying response processing..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-response-processing

echo "Verifying session mutation resets..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-session-mutation

echo "Verifying answer selection feedback..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-answer-selection

echo "Verifying chat request builder..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-chat-request-builder

echo "Verifying user message summaries..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-user-message-summary

echo "Verifying language policy..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-language-policy

echo "Verifying answer UI refresh..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-answer-ui-refresh

echo "Verifying study status UI refresh..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-study-status-ui-refresh

echo "Verifying source edit state reset..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-source-edit-reset

echo "Verifying selected-text UI policy..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-selection-ui-policy

echo "Verifying tutor window positioning..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-window-positioning

echo "Verifying history round-trip privacy..."
"${xcode_app_dir}/Contents/MacOS/${app_name}" --probe-history-roundtrip

if [ "${TUTORCLIP_VERIFY_OCR:-0}" = "1" ]; then
  echo "Verifying local OCR..."
  mkdir -p .build
  swiftc -target arm64-apple-macos14.0 -framework AppKit -framework Vision Scripts/verify_ocr.swift -o .build/verify_ocr
  .build/verify_ocr
else
  echo "Skipping OCR command-line diagnostic. Set TUTORCLIP_VERIFY_OCR=1 to run it."
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "Static verification passed."
