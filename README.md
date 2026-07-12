# TutorClip

TutorClip is a macOS 26+ personal SAT screenshot tutor.

## Screenshots

| Adaptive practice workspace | Knowledge map |
| --- | --- |
| ![TutorClip adaptive practice workspace](docs/screenshots/practice-workspace.png) | ![TutorClip SAT knowledge map](docs/screenshots/knowledge-map.png) |

| Vocabulary review |
| --- |
| ![TutorClip vocabulary review](docs/screenshots/vocabulary-review.png) |

## 使用方法

TutorClip 目前面向 Digital SAT Reading and Writing；不提供 SAT Math 的解题或练习。

1. 从 [Releases](https://github.com/dowellhz/TutorClip/releases) 下载并安装 `TutorClip.dmg`，把应用安装到 `Applications` 后启动。
2. 首次启动时，在“帮助与设置”中完成学习进度与历史记录选项，并输入 DeepSeek API Key。API Key 也可通过环境变量 `DEEPSEEK_API_KEY` 提供。
3. 正常启动会打开“今日学习”。直接完成系统安排的练习题，选择答案后可查看即时讲解、标记“会了 / 不会 / 错题”，并继续下一题。
4. 截图识题时按 `Shift + Command + O`，拖拽框选题目区域，再双击或按 Return 确认。首次使用需要授予 Screen Recording 权限。
5. OCR 完成后，在“题目”标签阅读和编辑文字；需要核对原图时切换到“截图”标签。复杂的文本下划线会在题目中恢复，填空位置则保留为 `_____`。
6. 使用底部操作快速进行“讲解整题”“翻译全文”“解析文章”“再练一题”或词汇提取；选中文字后只会显示翻译和生词操作。
7. 在“知识地图”查看 Reading and Writing 知识点掌握度；在“生词”完成当天复习；“历史”可查看已保存的题目和对话记录。

截图只在当前 OCR 会话内存中使用；关闭或替换该会话后会被丢弃。

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

Build a hardened-runtime app signed with Developer ID and create a signed DMG containing a native installer. The installer finds running TutorClip instances by bundle identifier, requests a normal quit, offers a confirmed force quit only after timeout, replaces the existing app, verifies its signature, and relaunches it:

```sh
make package-dmg
```

The installer is written to `.build/release/TutorClip.dmg`.

First installs default to `~/Applications` without an administrator prompt. Existing installations keep their current location; replacing `/Applications/TutorClip.app` uses the standard macOS administrator authorization dialog. Drag-to-Applications remains available as a manual fallback.

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

- Standard Dock app with a reusable main window and secondary menu bar access
- Today Practice, current question, Knowledge Map, History, and Vocabulary in one main-window navigation structure
- Configurable global shortcut, default `Shift + Command + O`
- Fullscreen capture overlay
- Capture rectangle adjustment before confirmation
- In-memory selected-region screenshot
- ScreenCaptureKit screenshot capture
- Local Apple Vision OCR
- Raycast-style normal tutor window that fronts once after capture and then follows standard macOS ordering
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
- Vocabulary learning loop with context-specific senses, due review, adaptive Again/Unsure/Known scheduling, search, status filters, editing, deletion, and source-question links
- Independent controls for detailed question/chat history and abstract learning progress
- Dedicated `mastery.sqlite` evidence store, separate from detailed session history
- History search, open, delete, and clear
- SAT Section, Domain, Skill, difficulty, error-reason, attempt, and review metadata
- Distinct Got It, Review, and Mistake learning flows with visible next steps
- Guided Review flow: separate no-answer Reading and Writing tutor prompt, persisted learning focus, focus-bound hidden-answer micro check, scaffolded practice, then independent verification; progress resumes from history
- First-answer locking with unscored retries, answer-confidence protection, and hint-aware 1/3/7/14/30-day scheduling
- Review question chains preserve the original, easier practice, and verification questions without mixing old chat into new AI context
- Local underline detection restores likely underlined OCR words in the Question view and sends only structured text cues to DeepSeek
- Event-based mastery calculation and 1/3/7/14/30-day review scheduling
- Teacher-style next-question scheduling using due review, errors, coverage, prerequisites, and varied verification
- Broad eight-answer initial diagnostic followed by targeted recovery, verification, and maintenance decisions
- Evidence-based mastery: simple points may pass quickly while ordinary and complex points require stronger varied evidence
- Weighted multi-skill evidence: the primary knowledge point receives full evidence while secondary associations remain diagnostic signals
- Natural daily stopping points: the initial diagnostic ends after eight valid responses and regular required practice ends after five per day, with optional challenge practice available
- Versioned Reading and Writing knowledge catalog with prerequisite and confusion relationships
- Today Review queues with Quick 5 and Review 10 continuous sessions
- Learning Center workspaces for due review, full history, and skill profiles
- History filters for status, section, domain, skill, difficulty, error reason, source, and date
- Skill mastery, accuracy, common-error, recommended-difficulty, reset, and targeted-practice actions
- AI-generated practice labeling, recent-question diversity, and independent answer/ambiguity validation
- Structured generated-question teaching contracts with purpose, prerequisites, distractor misconceptions, and verification basis
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
- Leaving or replacing an OCR session, or closing the main window, discards its screenshot.
- Detailed history stores OCR text, structured OCR data, and conversations only when enabled.
- Learning progress stores selected/correct answers, vocabulary cards, SAT skill metadata, answer attempts, mastery evidence, and review events only when enabled.
- The local data directory is owner-only (`0700`); settings, history, mastery, and API-key configuration files are owner-only (`0600`). Existing files are tightened when their owning store opens.
- API keys are not stored in Keychain, history, logs, or source code.

## Known Gaps

- Screen Recording and Accessibility are granted on the current verification Mac, and automated app-process capture diagnostics pass. The remaining gap is completing every interactive item in `VERIFY.md`, especially the multi-step guided-learning and History workspace flows.
