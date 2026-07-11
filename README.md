# TutorClip

TutorClip is a macOS 26+ personal SAT screenshot tutor.

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

Run an opt-in real Vision + DeepSeek table-question check without adding the source image to the repository:

```sh
make verify-table-ai \
  IMAGE=/absolute/path/to/question.png \
  EXPECTED_ANSWER=B \
  EXPECTED_TITLE='Expected table title'
```

This external integration check is separate from `make test`, so normal tests remain deterministic and network-free.

## DeepSeek API Key

TutorClip does not store the API key in Keychain.

## Release Packaging And Apple Notarization

Build a hardened-runtime app signed with Developer ID and create a signed drag-to-Applications installer:

```sh
make package-dmg
```

The installer is written to `.build/release/TutorClip.dmg`.

After storing Apple notary credentials in the Keychain profile named `TutorClip`, submit, wait, staple, and validate with:

```sh
make notarize-dmg
```

Or run the full pipeline with `make release-notarized`. Override `NOTARY_PROFILE` or `DEVELOPER_ID` when a different configured profile or certificate is required.

Key lookup order:

1. `DEEPSEEK_API_KEY` environment variable
2. `~/.tutorclip/config.json`
3. Temporary in-app input, stored only in memory

The Settings window keeps typed keys temporary by default. “Save to Local Config” explicitly writes the key to `~/.tutorclip/config.json` with owner-only `0600` permissions; “Remove Local Key” removes it again without putting the key in Keychain, SQLite, logs, or normal settings.

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
- SAT Section, Domain, Skill, difficulty, error-reason, attempt, and review metadata
- Distinct Got It, Review, and Mistake learning flows with visible next steps
- Guided Review flow: separate no-answer tutor prompt, reading/math-specific gap diagnosis, persisted learning focus, focus-bound hidden-answer micro check, scaffolded practice, then independent verification; progress resumes from history
- First-answer locking with unscored retries, answer-confidence protection, and hint-aware 1/3/7/14/30-day scheduling
- Review question chains preserve the original, easier practice, and verification questions without mixing old chat into new AI context
- Local underline detection restores likely underlined OCR words in the Question view and sends only structured text cues to DeepSeek
- Event-based mastery calculation and 1/3/7/14/30-day review scheduling
- Today Review queues with Quick 5 and Review 10 continuous sessions
- Learning Center workspaces for due review, full history, and skill profiles
- History filters for status, section, domain, skill, difficulty, error reason, source, and date
- Skill mastery, accuracy, common-error, recommended-difficulty, reset, and targeted-practice actions
- AI-generated practice labeling, recent-question diversity, and independent answer/ambiguity validation
- Editable AI SAT classification in the tutor window
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
- History stores OCR text, structured OCR data, conversations, selected/correct answers, vocabulary cards, SAT skill metadata, answer attempts, and review events only.
- API keys are not stored in Keychain, history, logs, or source code.

## Known Gaps

- Full end-to-end verification still needs to be completed with macOS Screen Recording permission granted. Use `VERIFY.md`.
