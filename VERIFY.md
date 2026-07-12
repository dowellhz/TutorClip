# TutorClip Verification Checklist

Use this checklist before claiming the design document is fully implemented.

## Functional Test Completion Gate

No release may describe automated functional testing as complete until every
automatable row below has current evidence. Run `make verify-automated` for the
complete repeatable suite (`make verify` plus visible UI tests). The manual
cases remain required release evidence because macOS TCC, Dock activation,
ScreenCaptureKit, and a real DeepSeek stream cannot be truthfully simulated by
an isolated XCTest process.

The current automated suite contains 116 deterministic behavior tests, 6
visible application-flow tests, and the static/privacy/probe gates invoked by
`make verify`. Treat `make verify-automated` as the single automated test
command; its result, rather than an individual test file, is the pass/fail
status for all repeatable in-app functionality.

| Area | Automated evidence | Required manual evidence |
| --- | --- | --- |
| Launch, normal windows, and exit | `TutorClipVisibleUITests` launch, Command-W, and Command-Q cases | Dock reopen, minimize, zoom, Spaces, and switching to another app |
| Menu bar and shortcuts | `SettingsBehaviorTests`, `QuestionRenderingBehaviorTests` | Menu-bar commands, configured global shortcut, invalid-key feedback |
| Capture safety | `InfrastructureBehaviorTests`, `CoreBehaviorTests` lifecycle tests | Screen Recording denied/granted, overlay drag/resize/Return/Esc, capture timeout recovery |
| Local OCR and formatting | OCR lifecycle, Markdown, table, and text probes in `make verify` | Real English/Chinese Vision OCR and a structured table capture using `TUTORCLIP_VERIFY_OCR=1 make verify` |
| DeepSeek interaction | stream decoder, payload, prompt, response, and validation tests | Configured-key streaming, remote failure/retry, and user-visible Chinese tutoring quality |
| Source and tutor interaction | `TutorSessionMutation`, rendering, selected-text, and answer-state tests | Editable OCR text, screenshot tab, selection popover placement, scrolling during a live stream |
| History and privacy | history/migration/privacy XCTest plus schema and payload scripts | Restart with each persistence toggle; inspect local data after a real capture |
| Adaptive learning and vocabulary | `SATLearningTests`, `GuidedLearningBehaviorTests`, `HistoryStoreBehaviorTests`, visible learning flow | Multi-day scheduling, real generated-question validation, and complete guided-learning recovery |
| Settings and diagnostics | `SettingsBehaviorTests`, config permission tests | TCC request screens, app-process diagnostics, launch-at-login behavior |

For each manual run, record the app build, macOS version, permission state,
network state, test date, and any failure in the release evidence. A skipped
manual row is a deferred test, not a pass.

## Required Human Intervention Only

Complete these cases manually. Every other repeatable behavior is covered by
`make verify-automated`; do not substitute repeated manual clicks for that
suite.

1. **Dock and window manager:** close the main window with Command-W, click the
   Dock icon to reopen it, then verify minimize, zoom, window cycling, and
   Space switching.
2. **Cross-app focus:** begin a real capture, switch to another app while OCR
   runs, and confirm TutorClip stays behind it after its one allowed post-capture
   activation.
3. **System menu-bar surface:** open the TutorClip status item and use Open,
   Capture, History, Knowledge Map, Settings, and a Recent Session when one is
   present.
4. **TCC-controlled capture overlay:** with Screen Recording granted, invoke the
   configured global shortcut; test Esc, a small drag, drag/move/edge-resize,
   Return, double-click confirmation, timeout recovery, and a multi-display
   edge selection.
5. **Real Vision output review:** capture English, Chinese, and structured-table
   questions; visually compare the selected region, screenshot preview, OCR
   text, preserved table rows/cells, and editable Markdown result.
6. **Native selection affordance:** select source text and confirm the action
   bar is placed accessibly and exposes only Translate and Vocabulary.
7. **Configured DeepSeek service:** using a non-test key, verify streaming,
   network failure/retry, and the quality of Explain, Translate, Vocabulary,
   Grammar, Passage Analysis, Practice Similar, and custom-question responses.
8. **Long-horizon learning behavior:** verify actual generated-question quality,
   guided teaching across its multi-step flow, and review scheduling across days.
9. **Persistence across a real restart:** exercise each history/learning toggle
   combination, quit and relaunch, then inspect the visible History, Knowledge
   Map, and Vocabulary results. Do not inspect or retain screenshots.
10. **Launch at login:** enable, log out/restart at a suitable time, and verify
    the app launches once without duplicate instances.

## Latest Verified Evidence (2026-07-12)

- Guided-learning automation now drives the full state chain from Needs Review
  through gap selection, foundation focus, a hidden-answer A/B/C/D micro-check,
  and successful transition to easier practice. A separate branch verifies that
  English assistance requires a concrete language barrier before its plan starts.
- Generated adaptive practice is pinned to current Digital SAT Reading and Writing:
  one short passage (or a Text 1/Text 2 pair for Cross-Text Connections), exactly
  one question, and one A/B/C/D set. Grouped `Questions 1-2` output is rejected
  locally before independent AI review and automatically retried.
- Standard application menus now provide Command-Q and common Edit shortcuts.
  App termination queues current-session persistence and synchronously drains both
  privacy-safe databases before process exit.
- Full `TUTORCLIP_VERIFY_OCR=1 make verify` passes after splitting question
  classification out of `TutorViewModel`; every maintained source file is below
  the enforced 450-line threshold.
- Vocabulary regression coverage now verifies multiple senses, edit/delete,
  adaptive review scheduling, source-session links, and persistence across a real
  mastery-database close and reopen.
- Generated questions that mention an underlined portion are rejected before AI
  review unless they identify the target with the explicit underline protocol.
  Rendering tests cover underline tags nested both inside and outside Markdown
  emphasis without exposing `<u>` or `**` markers to the student.
- Installed-app runtime diagnostics pass Screen Recording, a real ScreenCaptureKit
  capture, Accessibility, the user's configured global shortcut, local Vision OCR,
  history storage, and screenshot-persistence checks. Runtime verification accepts
  any successfully registered configured shortcut; default Shift-Command-O remains
  independently pinned by unit tests.

- `TUTORCLIP_VERIFY_OCR=1 make verify` passed: signed build, XCTest,
  privacy/schema gates, Markdown probes, and Vision `en-US`/`zh-Hans` support.
- The installed signed app passed three consecutive app-process capture health
  runs after the capture-probe window lifetime fix. The process remained alive
  and no newer TutorClip crash report was produced.
- A real global-shortcut capture produced an in-memory ScreenCaptureKit image,
  local structured Vision OCR, and DeepSeek text formatting. TutorClip fronted
  once at normal window level; switching to another app left it behind normally.
- A synthetic SAT linear-function table produced one structured Vision table
  with all four rows preserved. DeepSeek restored a GFM table and title; the
  formatted answer, independent verification answer, and explanation answer
  were all `B`.
- `Esc`, `Command + W`, process survival after window close, and main-window
  restoration on reopening were exercised on the installed signed app.
- The installed app migrated `.tutorclip` to `0700` and existing `settings.json`,
  `history.sqlite`, and `mastery.sqlite` to `0600`. Regression tests also cover
  old mastery evidence written before state snapshots were introduced.
- Adaptive-learning regression tests now cover persisted skill reset and review
  snoozing. Skill profiles are uniquely grouped by SAT skill, retain a zero-state
  after reset, and targeted practice chooses a concrete weakest knowledge point.
- Detailed history now round-trips classification and guided-learning flow only
  when learning progress is enabled; the privacy-off variant strips those fields.
  Manual mastery is honored by every scheduler branch, including saved recovery
  states and broad initial diagnostics.
- Question-chain snapshots are explicitly read-only: switching snapshots clears
  stale text selection and hides grading/global actions so an old question cannot
  record an answer against the current generated question.
- Independent generated-question validation now checks the teacher-selected
  question type and knowledge target itself. Resetting one knowledge point removes
  only that signal and preserves other points from the same multi-skill record.
- Review-workspace search, error-reason, source, and date filters now apply to the
  actual due queue. Skill reset and snooze wait for every database write, expose
  loading/disabled states, and report success only after all stores agree.
- User-corrected Section/Domain/Skill values cannot retain an incompatible AI
  knowledge target, preventing evidence from entering the wrong graph node. The
  History metrics use abstract mastery evidence even when detailed history is off.
- Menu-bar History and Knowledge Map now open a neutral main workspace without
  silently generating an adaptive question or spending an AI request. Closing that
  content-free workspace is verified not to create a blank history record.
- The installed signed app was exercised through the actual menu-bar History item
  after closing its window: no new `practice-similar` request appeared, and closing
  the neutral workspace logged `session-persistence-skipped empty-workspace=true`.
- Capture selection is now explicitly two-stage: mouse-up finalizes the rectangle,
  subsequent drags move or resize it, and only Return or double-click captures.
  Tiny accidental drags reset the selection instead of dismissing the overlay.
- A real installed-app synthetic drag logged `capture-mouse-up-finalized-awaiting-confirmation`
  and remained open without capture until the recovery timeout. The timeout is now
  inactivity-based and renews on each mouse-down/up so active adjustment is not cut off.
- The latest installed signed app completed the entire adjusted-capture path:
  selection `(320,560,380,260)` moved to `(420,520,380,260)`, a corner resize changed
  it to `(420,460,480,320)`, Return confirmed it, ScreenCaptureKit returned `976x656`,
  and the normal-level main window fronted once.
- Replacing a window with a different capture, history item, or generated question
  now persists the outgoing text and learning state first; same-session OCR updates
  bypass that write. A regression test verifies the previous session survives replacement.
- Low-confidence answers display only the selected choice until the user confirms
  the correct answer; they cannot reveal or grade against unverified metadata.
  Choosing an error reason no longer duplicates an already-scheduled mistake event,
  and an unscored retry starts a fresh duration clock without replacing attempt one.
- Newer saved learning states supersede older wrong attempts, and future review dates
  defer a point across every scheduler branch. Replacing a session also resets OCR
  edit mode and the prior learning-dock layout instead of leaking SwiftUI state.
- Regenerating a foundation explanation clears the prior learning focus first, so a
  malformed new protocol cannot unlock a check against stale teaching. Optional
  challenge questions now rotate through mastered points instead of always using
  the first catalog item, falling back to the student's strongest current point.
- “这一步懂了” no longer becomes disabled when DeepSeek omits the optional
  `LEARNING_FOCUS` wrapper; TutorClip recovers the focus from the current teaching
  context and still generates the quick check. Guided easy practice is explicitly
  recorded as `guidedRecovery`, while the original-difficulty question is recorded
  as `verification` without rewriting the source question's evidence metadata.
- Passing an original-difficulty verification now completes the guided loop instead
  of offering the same verification again. English-assisted original-question
  answers advance to independent verification because the assisted answer itself
  is not treated as independent mastery evidence.
- The missing-focus quick-check recovery has a direct view-model regression test,
  and guided-learning tests were split into their own focused test file before the
  settings suite crossed the repository's 450-line maintenance threshold.
- When the model omits `LEARNING_FOCUS`, quick-check recovery now uses the latest
  displayed assistant explanation as the validation focus (capped mechanically at
  1,200 characters). This keeps the button usable while still validating that the
  generated check matches what was just taught. Protocol support was split into a
  focused source file to keep `TutorLearningActions` below the size threshold.
- The installed signed app was observed in the real `英文辅助 · 含义检查 3/4`
  workspace with a generated A/B/C/D meaning check, proving the previously blocked
  “这一步懂了” transition reached the next stage. That run also exposed strict
  Foundation inline-Markdown parse failures; selectable question rendering now uses
  partial parsing so malformed model emphasis does not repeatedly fail the whole line.
- A real generated history question exposed `- (A)` Markdown-list choices while its
  passage began with “A historian…”. The old parser treated that prose as the lone A
  answer. Choice parsing now recognizes list and bold-wrapped labels, and suppresses
  any single-label result so prose cannot create a fake one-button answer control.
- The affected persisted session was audited directly: its independently validated
  answer was A and its evidence metadata was internally consistent. The defect was
  limited to rendering the available buttons, so reopening it with the new parser
  safely shows A/B/C/D without rewriting or discarding legitimate mastery evidence.
- Generated SAT questions are now rejected locally before the independent AI review
  unless all four displayed A/B/C/D labels and a matching declared answer are present.
  Guided micro-check protocol parsing applies the same four-choice invariant, so an
  incomplete model response can never become a partially gradeable user control.
- “Next Question” now performs exactly one mastery-evidence write, exposes a visible
  saving/disabled state, and advances only after that write succeeds. A failed write
  leaves the current question open with an actionable error instead of silently
  losing evidence or opening multiple next questions from repeated clicks.
- The success path is also covered with a temporary real mastery database: two rapid
  Next Question calls produce one durable attempt and exactly one navigation callback,
  proving navigation occurs after—not merely alongside—the successful write.
- Tutor-window close callbacks are now bound to a controller identity. Starting a
  new Quick 5 / Review 10 batch detaches the old identity before closing it, so a
  delayed old-window callback cannot clear the new controller, consume an extra
  review item, or skip the first question of the replacement batch.
- Detaching a tutor window explicitly cancels its OCR lifecycle before the stale
  close callback is ignored, preventing a late capture result from replacing a new
  review session. Settings and onboarding close callbacks also verify controller
  identity so rapid reopen/close sequences cannot clear a newer window reference.
- Menu-bar Recent Sessions is rebuilt from the live history store whenever the menu
  opens, and stored history sessions contain no screenshot. Shortcut policy tests
  pin the required Shift-Command-O default and rejection of Return, Tab, Space,
  Delete, Esc, and Forward Delete as unsafe global shortcut keys.

## Build

- Run `make verify-automated` for all repeatable automated functional tests.
- Run `make xcode-build`.
- Run `make xcode-build-signed` when Apple Development signing is available.
- Run `make verify`.
- Run `make verify-signed`.
- Confirm `.xcode-derived/Build/Products/Debug/TutorClip.app/Contents/MacOS/TutorClip` exists.
- Confirm `~/Applications/TutorClip.app/Contents/MacOS/TutorClip` exists after `make install-signed-local`.
- Confirm every maintained source, test, script, and project file stays below the
  450-line split threshold enforced by `make verify`.
- Confirm the Markdown pipeline probe reports preserved choice breaks and rendered line breaks during `make verify`.
- For a synthetic or user-supplied table question, run `make verify-table-ai IMAGE=... EXPECTED_ANSWER=... EXPECTED_TITLE=...` and confirm Vision finds a table, DeepSeek returns GFM, and both formatting and explanation answers match.
- Optional: inspect local signing identities with `security find-identity -v -p codesigning`. This shell may show zero standalone identities even when Xcode automatic signing succeeds.
- Confirm the signed app reports `TeamIdentifier=T84BKD53ZD` with `codesign -dv .xcode-derived/Build/Products/Debug/TutorClip.app`.
- Run `TUTORCLIP_VERIFY_OCR=1 make verify` to confirm Vision text recognition supports the required languages. The authoritative OCR content verification is the GUI capture flow below.
- Confirm history schema verification passes, or is skipped before history exists.
- Confirm DeepSeek payload privacy verification passes.

## Launch

- Run `make xcode-run` or open `.xcode-derived/Build/Products/Debug/TutorClip.app`.
- Run `make xcode-run-demo` and confirm a TutorClip window opens with a synthetic SAT question.
- Run `make xcode-run-demo-signed` and confirm the signed demo opens.
- Run `make run-signed-demo-local` and confirm the stable local signed demo opens.
- Confirm the menu bar item appears.
- Confirm TutorClip has a Dock icon and normal launch opens the main window to Today Practice.
- Confirm the sidebar reaches Today Practice, Current Question, Knowledge Map, History, and Vocabulary without opening floating panels.
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
- Confirm the normal TutorClip main window opens and comes to the front once.
- Click another app and confirm TutorClip moves behind it instead of remaining always on top.
- Wait for OCR to finish and confirm completion does not steal focus again.
- Confirm `Command + W` closes the main window without quitting TutorClip or disabling the global shortcut.
- Click the Dock icon and confirm the main window reopens.
- Confirm `Esc` does not close the main window.
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
- Open Vocabulary and confirm due cards hide the meaning until Show Answer; Again, Unsure, and Known update the schedule and status.
- Confirm search and status filters work, cards can be edited and deleted, different meanings of the same word remain separate, and Open Source returns to saved source questions.
- Click Analyze Passage and confirm the passage is explained without directly solving the question.
- Click Practice Similar and confirm a new SAT question appears in the Question tab with selectable answer choices.
- Select an answer choice for a practice question and confirm the UI shows whether it is correct.
- Select text and test Translate and Vocabulary only.
- Ask a custom question and confirm OCR context is used.

## History And Privacy

- Navigate away from the active OCR question and confirm its screenshot is discarded.
- Close the main window.
- Confirm the screenshot is no longer visible when reopening the history session.
- Disable detailed history but keep learning progress enabled; answer a generated question and confirm mastery/review evidence remains without OCR text or conversation content.
- Disable learning progress but keep detailed history enabled; confirm the question and chat can remain without updating durable mastery evidence.
- Disable both controls, capture again, close, and confirm the session is not saved.
- Confirm no screenshots are written to `.tutorclip` or project files.
- Confirm API key is not written to SQLite, settings JSON, logs, or source files.

## SAT Learning System

- On normal launch, confirm Today Practice automatically prepares a teacher-selected question or shows an actionable API/network error.
- Confirm a simple knowledge point can reach initial mastery after one valid independent diagnostic answer.
- Complete several first-run questions and confirm the initial diagnostic samples different SAT question types before narrowing into remediation.
- After a scored generated question, click Next Question and confirm TutorClip waits for evidence persistence before selecting the next objective.
- Confirm hint-assisted, ambiguous, or failed-validation questions do not count as independent mastery evidence.
- Confirm recent mistakes and due reviews are chosen before uncovered low-priority material.
- Confirm ordinary or complex knowledge requires varied verification rather than a fixed four-correct quota.
- Confirm the Knowledge Map contains Reading and Writing nodes and no Math nodes.
- Disable detailed history while keeping learning progress enabled and confirm mastery survives restart through `mastery.sqlite` without retaining question text.
- When all scheduled points are stable, confirm Today Practice shows completion instead of an endless required feed.

- Confirm OCR formatting assigns Section, Domain, Skill, difficulty, and confidence when DeepSeek can determine them.
- Correct an AI classification in the tutor window and confirm History shows the edited values.
- Click Got It and confirm the question becomes pending verification with a future review date.
- Click Review and confirm a foundational teaching request starts and the question is due today.
- Confirm clicking Review first asks where the student is stuck and does not immediately start a long AI response.
- Choose a gap, start learning, and confirm only the Foundation 1/3 actions are shown.
- Confirm guided teaching never reveals or eliminates toward the original answer before the student answers.
- For Reading/Writing, confirm English, task-meaning, concept, and application gaps produce different teaching strategies.
- Capture a Math question and confirm TutorClip reports it as unsupported without generating an answer or follow-up practice.
- Confirm Change Learning Gap returns to diagnosis without losing the original difficulty.
- Continue to Quick Check 2/3 and confirm the protocol answer never appears in streamed chat text.
- Confirm the quick check tests the displayed learning focus rather than an unrelated passage detail.
- Pass the quick check, complete the easier question, and confirm original-difficulty verification becomes available.
- Confirm scaffolded easy practice is recorded as hint-assisted and self-reported Got It does not count as independent mastery.
- Submit an answer and confirm the first result locks; use Try Again and confirm the retry does not replace the first scored attempt.
- Confirm a first independent correct answer schedules one day later, while a hint-assisted correct answer remains due for independent verification.
- For a low-confidence AI answer, confirm no automatic grading occurs until the user confirms the correct answer.
- Generate easier and verification questions, then use the Question Chain menu to revisit the original and every generated question.
- During streaming, scroll upward and confirm TutorClip does not force the view back to the bottom on every token batch.
- Capture synthetic underlined text and confirm TutorClip shows a visual-cue notice and underlines the detected word in the Question view; compare against Screenshot for false positives.
- Close and reopen the history session during the flow and confirm the current step is restored.
- Select a wrong answer, choose an error reason, and confirm mistake analysis starts and the review is scheduled.
- Generate a practice question and confirm it is labeled AI Generated and only appears after independent validation.
- Open History and confirm Review, Skills, and History workspaces are available.
- Confirm Quick 5 and Review 10 advance to the next due question after closing the current tutor window.
- Snooze a due question and confirm it leaves today's queue until tomorrow.
- Filter history by status, Section, Domain, Skill, difficulty, error reason, source, and date.
- Expand Learning Timeline and confirm recent attempts and review states appear.
- Confirm Skill Profiles show mastery, accuracy, question count, common error, and recommended difficulty.
- Start targeted practice from a Skill Profile and confirm the generated question matches that skill.
- Reset a Skill Profile and confirm its attempts, review schedule, and mastery return to the initial state.
