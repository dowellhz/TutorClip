# TutorClip Verification Checklist

Use this checklist before claiming the design document is fully implemented.

## Build

- Run `make xcode-build`.
- Run `make xcode-build-signed` when Apple Development signing is available.
- Run `make verify`.
- Run `make verify-signed`.
- Confirm `.xcode-derived/Build/Products/Debug/TutorClip.app/Contents/MacOS/TutorClip` exists.
- Confirm `~/Applications/TutorClip.app/Contents/MacOS/TutorClip` exists after `make install-signed-local`.
- Confirm every source file is under 500 lines.
- Confirm the Markdown pipeline probe reports preserved choice breaks and rendered line breaks during `make verify`.
- Optional: inspect local signing identities with `security find-identity -v -p codesigning`. This shell may show zero standalone identities even when Xcode automatic signing succeeds.
- Confirm the signed app reports `TeamIdentifier=T84BKD53ZD` with `codesign -dv .xcode-derived/Build/Products/Debug/TutorClip.app`.
- Optional: run `TUTORCLIP_VERIFY_OCR=1 make verify` to confirm Vision text recognition supports the required languages. The authoritative OCR content verification is the GUI capture flow below.
- Confirm history schema verification passes, or is skipped before history exists.
- Confirm DeepSeek payload privacy verification passes.

## Launch

- Run `make xcode-run` or open `.xcode-derived/Build/Products/Debug/TutorClip.app`.
- Run `make xcode-run-demo` and confirm a TutorClip window opens with a synthetic SAT question.
- Run `make xcode-run-demo-signed` and confirm the signed demo opens.
- Run `make run-signed-demo-local` and confirm the stable local signed demo opens.
- Confirm the menu bar item appears.
- Open Settings from the menu bar.
- Open History from the menu bar.
- If history exists, confirm Recent Sessions in the menu bar can reopen a session.

## Permissions

- In Settings, confirm Screen Recording status is visible.
- In Settings, confirm Accessibility status is visible.
- Run Settings diagnostics and confirm the Screen Recording row is visible.
- Run Settings diagnostics and confirm the Accessibility row is visible.
- Run `make diagnose-app-signed-local` and confirm it exits successfully. It fails if app-process diagnostics do not include `实际截屏=PASS` / `Capture Probe=PASS`.
- If not granted, run `make request-permissions-signed-local` or click Request Permission.
- Grant Screen Recording in macOS System Settings.
- Restart TutorClip if macOS asks for restart.
- Quit TutorClip and open a new command window after changing TCC permissions.
- Refresh Settings and confirm status changes to Granted.

## Shortcut

- Confirm default shortcut shows `Shift + Command + O`.
- Confirm Settings shows the shortcut registration status.
- Record a new shortcut with a modifier key.
- Confirm invalid keys such as Esc or Return are rejected.
- Save and confirm the registration message updates.

## Capture And OCR

- Press the configured shortcut.
- Confirm the fullscreen capture overlay appears.
- Drag a region.
- Confirm the selected rectangle can be moved and resized from edges/corners.
- Press Return to capture.
- Confirm the TutorClip floating window opens.
- Confirm `Command + W` closes the tutor window.
- Confirm `Esc` does not close the tutor window.
- If ScreenCaptureKit fails or stalls, confirm the overlay disappears and TutorClip reports a screenshot failure instead of trapping input.
- Confirm the screenshot preview is visible for the current session.
- Confirm the Question tab is selected by default.
- Confirm the Question tab shows AI-formatted Markdown text with passage, question stem, and A/B/C/D choices separated into readable paragraphs.
- Confirm the Question tab can enter editing mode and edited text becomes the canonical text sent to DeepSeek.
- Confirm the Screenshot tab shows the current in-memory screenshot preview.
- Select text in the Question tab and confirm the PopClip-style action bar appears near the selected text without covering it when possible.
- Confirm selected-text actions are limited to Translate and Vocabulary.

## DeepSeek

- Configure an API key using one of:
  - `DEEPSEEK_API_KEY`
  - `~/.tutorclip/config.json`
  - temporary in-app input
- Confirm the API key is not stored in Keychain or history.
- Click Explain All and confirm streaming output appears.
- Click Translate All and confirm Chinese translation appears.
- Click Vocabulary and confirm difficult words, phrases, and fixed expressions from the passage are extracted.
- Click Analyze Passage and confirm the passage is explained without directly solving the question.
- Click Practice Similar and confirm a new SAT question appears in the Question tab with selectable answer choices.
- Select an answer choice for a practice question and confirm the UI shows whether it is correct.
- Select text and test Translate and Vocabulary only.
- Ask a custom question and confirm OCR context is used.

## History And Privacy

- Close the tutor window.
- Confirm the screenshot is no longer visible when reopening the history session.
- Confirm OCR, conversation, selected answers, correct answers, study status, and vocabulary cards are saved only when history is enabled.
- Disable history, capture again, close, and confirm the session is not saved.
- Confirm no screenshots are written to `.tutorclip` or project files.
- Confirm API key is not written to SQLite, settings JSON, logs, or source files.
