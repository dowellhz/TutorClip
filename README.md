# TutorClip

TutorClip is a macOS 14+ personal SAT screenshot tutor.

## Build

```sh
make xcode-build
```

The app bundle is generated at:

```text
.xcode-derived/Build/Products/Debug/TutorClip.app
```

## Run

```sh
make xcode-run
```

Run the Apple Development signed app directly from the Xcode build:

```sh
make xcode-run-signed
```

Install and run the signed app from a stable macOS privacy-permission path:

```sh
make install-signed-local
make run-signed-local
```

If `make verify-signed` just succeeded and Xcode account state is flaky in the current command window, install the existing signed build without rebuilding:

```sh
make install-current-signed-local
```

Run a synthetic SAT session without screen-recording permission:

```sh
make xcode-run-demo
```

Signed demo run from Xcode output:

```sh
make xcode-run-demo-signed
```

Signed demo run from `~/Applications`:

```sh
make run-signed-demo-local
```

Request macOS permissions from the installed app bundle:

```sh
make xcode-request-permissions
```

Use the signed permission request from the stable local app:

```sh
make request-permissions-signed-local
```

This opens `~/Applications/TutorClip.app` and lets the app process request Screen Recording and Accessibility. After granting permissions, quit TutorClip and open a new command window before running diagnostics again.

Check TutorClip's permission state:

```sh
make xcode-diagnose
```

Check the signed local app:

```sh
make diagnose-signed-local
```

Check permissions from the signed app process itself:

```sh
make diagnose-app-signed-local
```

This app-process diagnostic also runs a small in-memory ScreenCaptureKit probe and fails if any critical row is `WARN` or `FAIL`. The output must include `实际截屏=PASS` or `Capture Probe=PASS`; a plain Screen Recording permission check is not enough to prove screenshots will contain real app content.

Signing:

TutorClip supports Apple Development signing through Xcode automatic signing. DualFlipClock used team `T84BKD53ZD`; TutorClip uses the same team and bundle id `com.linlu.TutorClip`.

```sh
make xcode-build-signed
```

The signed Xcode build should show `TeamIdentifier=T84BKD53ZD` in:

```sh
codesign -dv .xcode-derived/Build/Products/Debug/TutorClip.app
```

## Verify

```sh
make verify
make verify-signed
```

## DeepSeek API Key

TutorClip does not store the API key in Keychain.

Key lookup order:

1. `DEEPSEEK_API_KEY` environment variable
2. `~/.tutorclip/config.json`
3. Temporary in-app input, stored only in memory

Example config:

```json
{
  "deepseekApiKey": "your-api-key",
  "deepseekBaseURL": "https://api.deepseek.com",
  "model": "deepseek-chat"
}
```

## Implemented

- Menu bar resident app
- Configurable global shortcut, default `Shift + Command + O`
- Fullscreen capture overlay
- Capture rectangle adjustment before confirmation
- In-memory selected-region screenshot
- ScreenCaptureKit screenshot capture
- Local Apple Vision OCR
- Raycast-style floating tutor window
- Current-session screenshot preview
- Question tab shown by default with AI-formatted Markdown text
- Screenshot tab for the current in-memory screenshot preview
- OCR formatting state shown in the Question tab
- Editable OCR text
- Native OCR text selection capture
- PopClip-style selected-text actions
- DeepSeek streaming chat
- SAT tutor prompt
- Quick actions: Recapture, Vocabulary, Analyze Passage, Practice Similar, Translate All, Explain All
- Selected-text actions: Translate, Vocabulary
- SQLite history for OCR, conversation, and learning metadata only
- History search, open, delete, and clear
- Settings window
- Launch-at-login setting
- Settings diagnostics for permissions, shortcut, API key, OCR support, history storage, and screenshot persistence
- Menu bar recent sessions submenu
- Synthetic demo SAT session via `make run-signed-demo-local`
- Optional local OCR diagnostic via `TUTORCLIP_VERIFY_OCR=1 make verify`
- History SQLite schema privacy check via `make verify`
- DeepSeek text-only payload privacy check via `make verify`

## Privacy

- Screenshots are never saved to disk.
- Closing the tutor window discards the screenshot.
- History stores OCR text, structured OCR data, conversations, selected answers, correct answers, study status, and vocabulary cards only.
- API keys are not stored in Keychain, history, logs, or source code.

## Known Gaps

- Full end-to-end verification still needs to be completed with macOS Screen Recording permission granted. Use `VERIFY.md`.
