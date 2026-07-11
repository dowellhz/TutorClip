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
- For a synthetic or user-supplied table question, run `make verify-table-ai IMAGE=... EXPECTED_ANSWER=... EXPECTED_TITLE=...` and confirm Vision finds a table, DeepSeek returns GFM, and both formatting and explanation answers match.
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

## SAT Learning System

- Confirm OCR formatting assigns Section, Domain, Skill, difficulty, and confidence when DeepSeek can determine them.
- Correct an AI classification in the tutor window and confirm History shows the edited values.
- Click Got It and confirm the question becomes pending verification with a future review date.
- Click Review and confirm a foundational teaching request starts and the question is due today.
- Confirm clicking Review first asks where the student is stuck and does not immediately start a long AI response.
- Choose a gap, start learning, and confirm only the Foundation 1/3 actions are shown.
- Confirm guided teaching never reveals or eliminates toward the original answer before the student answers.
- For Reading/Writing, confirm English, task-meaning, concept, and application gaps produce different teaching strategies.
- For Math, confirm concept/formula, modeling, execution, and graph/function gaps are available.
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
