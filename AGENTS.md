# TutorClip Agent Guidelines

These rules define how future coding work on TutorClip should be done.

## Product Contract

TutorClip is a personal macOS 26+ adaptive SAT tutor. Screenshot OCR is a fast
question-ingestion path, not the application's only entry point.

Required behavior:

- App name is `TutorClip`.
- The app is a standard macOS app with a Dock presence and a normal main window.
- The menu bar item remains available as a secondary quick-access surface.
- Normal launch opens the main window to adaptive daily practice.
- Default global shortcut is `Shift + Command + O`.
- Shortcut must remain configurable.
- The shortcut opens a screenshot selection overlay.
- OCR must run locally with Apple Vision.
- Structured document OCR exclusively uses `RecognizeDocumentsRequest`; table rows and cells must be preserved for DeepSeek text context.
- DeepSeek is the LLM provider.
- Default AI response language is Chinese.
- The AI persona is an experienced SAT tutor.
- The main UI should feel like Raycast.
- Text selection actions should feel like PopClip.
- OCR questions and generated practice use the same main window and learning model.
- The main window must use normal macOS window ordering and must not remain always on top.

## Privacy Rules

These are hard requirements.

- Never save screenshots to disk.
- Screenshots may exist only in memory for the current active OCR session.
- Leaving or replacing the OCR session, or closing the main window, must discard its screenshot.
- TutorClip may automatically send the user-selected screenshot region to a configured remote vision/OCR provider when local OCR cannot reliably recover a Reading and Writing question. This automatic fallback does not require a separate per-capture authorization prompt.
- Remote image transfer must contain only the region deliberately selected by the user, must use encrypted transport, and must be used only to recover the current question. TutorClip must not send the full screen when the user selected a smaller region.
- TutorClip must release the remote-request image payload and response-associated image data after the current OCR request finishes, fails, or is cancelled. Remote fallback must respect OCR session identity and cancellation so stale results cannot mutate a replacement session.
- A remote vision/OCR provider must not be described as local processing. Product UI must disclose that selected screenshots may be sent automatically for recognition when remote fallback is configured.
- Saved question and conversation history may contain OCR text, structured OCR metadata, and conversation messages only; it must remain independently controllable by the user.
- Saved learning progress may contain selected answers, correct answers, study status, mastery evidence, review scheduling, and vocabulary cards only; it must remain independently controllable by the user.
- First-run UI must clearly disclose the separate learning-progress and question/conversation-history controls before either category is persisted.
- History must not save screenshots or raw screen images.
- DeepSeek receives text context only. Because the official DeepSeek API does not accept image input, screenshot images may be sent only to the separately configured vision/OCR provider; only the resulting text context may be sent to DeepSeek.
- Do not store the DeepSeek API key in Keychain.
- Do not hardcode API keys.
- Do not write API keys into logs, history, SQLite, settings, or source files.
- `ConfigLoader` exclusively owns explicit API-key persistence to `~/.tutorclip/config.json`; the Settings UI may save or remove that key only through user-invoked actions, and the file must use owner-only `0600` permissions.

API key lookup order:

1. `DEEPSEEK_API_KEY` environment variable
2. `~/.tutorclip/config.json`
3. Temporary in-app memory value

## Stability Rules

System stability is a hard requirement.

- Any behavior that can freeze macOS, monopolize input, block the main thread, trap the user in an overlay, or otherwise make the system feel stuck must be treated as high risk and implemented cautiously.
- Screenshot capture, global event monitors, window levels, keyboard interception, and permission flows must always have clear cancellation and recovery paths.
- Long-running work such as OCR, networking, history writes, or image processing must not run synchronously on the main thread.
- Capture may activate the app once after selection, but OCR completion must not steal focus again.
- Before changing capture or window activation behavior, consider failure modes where the app cannot receive input, cannot dismiss an overlay, repeatedly steals focus, or prevents the user from switching apps.

## UI Rules

The interface should be clean, modern, and work-focused.

- Prefer restrained macOS-native surfaces.
- Use neutral backgrounds and subtle dividers.
- Use teal/blue-green only as an accent.
- Do not build a marketing page.
- Do not use large decorative gradients.
- Do not use nested cards.
- Do not add decorative illustrations.
- Prioritize OCR readability and tutor response clarity.
- The main window, Settings, History, and Knowledge Map use normal macOS window levels.
- Clicking another app lets TutorClip move behind it normally and must not close TutorClip.
- `Command + W` closes the main window without quitting the app; the global shortcut remains available.
- Clicking the Dock icon reopens the main window when no main window is visible.
- `Command + Q` quits the app.
- `Esc` cancels screenshot capture, but should not accidentally close the main window.
- The main window uses standard macOS minimize, zoom, window cycling, and Space behavior.

## Normal Launch Flow

1. User launches TutorClip normally or reopens it from the Dock.
2. TutorClip opens its main window to Today Practice.
3. A teaching scheduler selects the most valuable next knowledge point and question purpose from the student's mastery evidence.
4. DeepSeek generates and validates a structured SAT question, or the UI shows an actionable setup, loading, or recovery state.
5. User answers and receives immediate, appropriately sized instruction.
6. The answer records mastery evidence immediately; persistence must not depend on closing the window.
7. The scheduler chooses whether to advance, verify, reteach, reduce difficulty, increase difficulty, or stop for the day.

## Screenshot Flow

1. User presses `Shift + Command + O`.
2. TutorClip shows a fullscreen capture overlay.
3. User selects a region.
4. TutorClip captures the region in memory.
5. TutorClip restores and activates the normal main window once, switches it to the new OCR session, and shows OCR progress.
6. TutorClip runs local OCR without blocking the main thread.
7. Left side shows the current question text by default, with a screenshot tab available.
8. Right side shows SAT Tutor chat.
9. User can ask questions or use quick actions.
10. DeepSeek streams a Chinese explanation.
11. After that one activation, switching to another app places TutorClip behind it normally; OCR completion must not reactivate TutorClip.
12. Leaving or replacing the OCR session, or closing the main window, discards the screenshot.
13. OCR text, chat, and learning progress follow their respective user-controlled persistence settings.

## Adaptive Learning Contract

TutorClip behaves like an experienced SAT teacher, not a uniform random-question feed.

- The teaching scheduler must choose questions using prerequisites, due review, recent OCR mistakes, weak or unverified points, uncovered points, transfer checks, and session pacing.
- Do not require a fixed number of correct answers for every knowledge point.
- A simple point may reach initial mastery after one strong independent diagnostic response.
- Ordinary points should normally require independent evidence across more than one presentation.
- Complex points should require appropriately varied evidence such as foundation, application, or transfer.
- Hint-assisted, ambiguous, invalid, or unverified generated questions must not count as independent mastery evidence.
- Wrong answers must not blindly reset all progress; concept gaps, reading errors, careless mistakes, and language barriers are different evidence.
- Mastery is staged rather than boolean: unseen, learning, initially mastered, stably mastered, and due for review.
- When all currently scheduled material is complete, show a clear completion state and optional challenge or free-practice paths; do not create an endless mandatory feed.
- Stable knowledge remains subject to increasingly infrequent maintenance checks.
- New users begin with a short broad diagnostic so clearly easy material can be passed quickly.

The knowledge model must extend beyond a flat catalog. It should support prerequisite, easily-confused, composite, and difficulty relationships. TutorClip covers SAT Reading and Writing only and must not claim, generate, teach, or track SAT Math mastery.

Generated practice must use a structured contract containing the target knowledge point, prerequisites, purpose, difficulty, correct answer, distractor misconceptions, and explanation basis. Questions that fail quality or answer validation must not affect mastery.

## Required Actions

Left source tabs:

- Question
- Screenshot

Global actions:

- Recapture
- Vocabulary
- Analyze Passage
- Practice Similar
- Translate All
- Explain All

Selected-text actions:

- Translate
- Vocabulary

OCR text must remain editable from the question view. Edited OCR text is the canonical text sent to DeepSeek.

## SAT Tutor Prompt Rules

The assistant must teach, not just answer.

For Reading/Writing:

- Explain the source text.
- Explain what the question asks.
- Explain why the correct answer is correct.
- Explain why wrong choices are wrong.
- Identify vocabulary, grammar, or reasoning points.

For Math, state that TutorClip does not support the question. Do not reconstruct formulas, solve it, generate an answer, or create follow-up practice.

If OCR is incomplete or ambiguous, the model should say so and avoid inventing missing content.

## AI-First Text Processing Rules

When a text task requires language understanding, layout judgment, or SAT domain judgment, prefer DeepSeek over local heuristics.

- Use AI for OCR cleanup, question layout, answer choice formatting, translation, vocabulary extraction, grammar analysis, passage analysis, question type detection, answer extraction, and explanation structure whenever the result is user-facing.
- Do not build broad regular-expression pipelines or custom local formatters for OCR text, Markdown layout, answer choice splitting, grammar cleanup, or question reconstruction if AI can reasonably do the task.
- Local code may parse explicit protocol wrappers from AI output, such as `FORMATTED_QUESTION`, `QUESTION_METADATA`, `Answer:`, and `Type:`, but it should not reinterpret or rewrite the Markdown content inside those blocks.
- Local code may do only mechanical, non-semantic cleanup when necessary, such as trimming surrounding whitespace, removing code fence wrappers, validating empty output, or preserving the original OCR text on failure.
- If DeepSeek output is malformed, prefer improving the prompt and structured output contract before adding local regex fixes.
- If a local fallback is unavoidable for stability, keep it minimal, document why AI cannot be used for that exact case, and never let it override a valid AI-formatted result.
- UI rendering should render the Markdown it receives. It should not perform extra OCR formatting, option splitting, or paragraph reconstruction.
- Any new text-processing regex must be narrow, protocol-level, and justified in code review. It must not become a hidden second formatter.

## Architecture Rules

Preferred stack:

- SwiftUI for main app UI.
- AppKit for the standard main window, menu bar, capture overlay, shortcut handling, activation behavior, and native text selection behavior.
- Apple Vision for local OCR.
- URLSession for DeepSeek streaming.
- SQLite for history.
- ServiceManagement for launch at login.

Core modules should stay separated:

- `AppCoordinator`
- `MenuBarController`
- `ShortcutManager`
- `CaptureOverlayController`
- `OCRService`
- `OCRRequestLifecycle`
- `TutorWindowController`
- `TutorViewModel`
- `TeachingScheduler`
- `MasteryEvidenceStore`
- `DeepSeekClient`
- `PromptBuilder`
- `HistoryStore`
- `SettingsStore`
- `ConfigLoader`

Avoid mixing UI code, network code, persistence, OCR, and prompt construction in the same type.

`OCRRequestLifecycle` owns cancellation and session identity checks for in-memory screenshot OCR. Replacing, leaving, or closing an OCR session must prevent an older OCR result from mutating the current window.

`TeachingScheduler` owns selection of the next learning objective, question purpose, and target difficulty. `AppCoordinator` may request and present that decision but must not implement teaching policy itself.

`MasteryEvidenceStore` owns durable, versioned mastery evidence and vocabulary-card review scheduling separately from question and conversation history. Vocabulary cards may store text context and source session identity, but never screenshots or raw screen images.

## Code Size And Maintainability Rules

These limits are mandatory unless the user explicitly approves an exception.

- No source file should exceed 500 lines.
- If a file approaches 450 lines, split it before adding more behavior.
- Prefer one primary responsibility per file.
- Prefer one primary type per file, except for very small helper enums or private view components.
- Keep SwiftUI view files focused on layout and user interaction. Move business logic into view models or services.
- Keep service files focused on side effects such as OCR, persistence, network, capture, or permissions.
- Keep model files free of AppKit/SwiftUI behavior unless the model explicitly represents UI state.
- Avoid large catch-all utility files.
- Avoid adding unrelated behavior to `AppCoordinator`; it should orchestrate modules, not implement module internals.
- New privacy-sensitive behavior must have an explicit owner type and must be mentioned in this file if it changes screenshots, API keys, history, or DeepSeek payloads.

Function and type guidance:

- Keep individual functions under about 80 lines when practical.
- If a function has several phases, extract named private helpers.
- If a SwiftUI `body` becomes hard to scan, split it into private subviews or separate files.
- If a type needs more than one unrelated dependency group, consider splitting the type.
- Prefer explicit names over dense clever code.
- Add comments only for non-obvious behavior, privacy constraints, coordinate conversions, permission handling, or API protocol details.

Human readability requirements:

- Code should read top-down in the same order a human would reason about the feature: public API first, then state transitions, then private helpers.
- Avoid clever one-liners when they hide control flow, side effects, or error handling. Prefer a few clear lines with named intermediate values.
- Name methods by the user-visible intent or domain action, not by implementation details. For example, prefer `applyGeneratedQuestion` over `setTextAndClearStuff`.
- Do not encode product behavior in scattered conditionals. If an action has special behavior, put that behavior behind a named method or small type.
- Keep related state changes together. If selecting an answer changes `selectedAnswer`, UI result text, history, or study status, make the ownership explicit and do not rely on incidental SwiftUI refreshes.
- When mutating an `ObservableObject` owned by another `ObservableObject`, make sure view updates are forwarded intentionally. Do not assume nested `@Published` properties will refresh parent views.
- Avoid fragile parsing with broad regular expressions for core behavior. Prefer structured model output, typed parsers, or small purpose-specific parsers with examples.
- Do not silently swallow important failures. If a user action appears to do nothing, add a visible fallback state or a log entry that explains why.
- Keep prompt text, UI layout, persistence, and network streaming in separate files. A prompt change should not require reading window layout code.
- If a file crosses 450 lines because of new work, split it in the same change before adding more behavior.
- If a bug is caused by file size, mixed responsibilities, or unclear state ownership, fix the structure first instead of layering another conditional on top.
- Prefer boring, local abstractions over broad utility objects. A helper should have one reason to exist and a name that says exactly what it owns.
- For UI controls, the state source, action handler, and resulting visible feedback must be traceable from the code without jumping through many files.
- Every non-trivial user action should have a clear success path, empty/error path, and disabled/loading behavior.

Review checklist for maintainability:

- Can a new engineer find the owner of this behavior in under a minute?
- Can the user-visible flow be followed without reading unrelated modules?
- Does each edited file still have one main responsibility?
- Are model changes, persistence changes, prompt changes, and UI changes separated enough to test independently?
- Are there any hidden dependencies on previous chat messages, stale OCR text, old screenshots, or old selected state?
- Are all new states reset when starting a new capture, generated practice question, or history session?
- Does the build still pass, and did the change avoid introducing a new warning unless documented?

File and repository hygiene:

- Do not commit generated build output such as `.build/`.
- Do not commit local config files such as `~/.tutorclip/config.json`.
- Keep `.gitignore` updated for generated output, local databases, secrets, and private captured material.
- Do not add API keys, screenshots, OCR samples from private material, or chat transcripts to the repository.
- Do not create broad "misc" files.
- If adding tests or fixtures later, use synthetic data only.

## Build Rules

Current build command:

```sh
make build
```

Current run command:

```sh
make run
```

The generated app bundle is:

```text
.build/TutorClip.app
```

Before reporting work as complete, run:

```sh
make build
```

Warnings are acceptable only if they are documented and do not block functionality. Deprecated screenshot or window APIs should be replaced when current macOS APIs provide equivalent behavior.

## Known Gaps To Preserve As Work Items

Do not claim the full product is complete until these are addressed or explicitly deferred by the user:

- Complete the full manual flow in `VERIFY.md` on macOS with Screen Recording permission granted.
- Replace deprecated screenshot/window APIs when ScreenCaptureKit coverage is sufficient for the capture flow.
- Keep expanding diagnostic probes for OCR formatting, Markdown rendering, and selection popover placement as regressions are found.
