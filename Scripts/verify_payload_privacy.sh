#!/bin/sh
set -eu

echo "Checking DeepSeek payload privacy..."

rg -n "NSImage|CGImage|base64|screenshot|screenshotInMemory" Sources/TutorClip/PromptBuilder.swift Sources/TutorClip/DeepSeekClient.swift && {
  echo "DeepSeek prompt/client contains image, screenshot, base64, or suspicious payload terms."
  exit 1
}

rg -n "request\\.httpBody\\s*=\\s*try JSONEncoder\\(\\)\\.encode\\(body\\)" Sources/TutorClip/DeepSeekClient.swift >/dev/null || {
  echo "DeepSeek request body encoding path changed; review payload privacy."
  exit 1
}

rg -n "struct DeepSeekRequest" Sources/TutorClip/DeepSeekClient.swift >/dev/null || {
  echo "DeepSeekRequest model missing."
  exit 1
}

echo "DeepSeek payload privacy verification passed."

echo "Checking Markdown rendering does not fetch model-authored images..."
rg -n "markdownImageProvider\(\.asset\)" Sources/TutorClip/ChatMessageContentText.swift >/dev/null || {
  echo "Block Markdown images must use the local asset provider."
  exit 1
}
rg -n "markdownInlineImageProvider\(\.asset\)" Sources/TutorClip/ChatMessageContentText.swift >/dev/null || {
  echo "Inline Markdown images must use the local asset provider."
  exit 1
}

echo "Markdown external image privacy verification passed."
