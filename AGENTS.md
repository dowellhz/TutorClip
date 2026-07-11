# TutorClip Agent Guidelines

These rules define how future coding work on TutorClip should be done.

## Product Contract

TutorClip is a personal macOS 26+ SAT screenshot tutor.

Required behavior:

- App name is `TutorClip`.
- The app is a menu bar resident macOS app.
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

## Privacy Rules

These are hard requirements.

- Never save screenshots to disk.
- Screenshots may exist only in memory for the current session.
- Closing the tutor window must discard the screenshot.
- History may save OCR text, structured OCR metadata, conversation messages, and learning metadata only.
- Learning metadata means selected answers, correct answers, study status, and vocabulary cards.
- History must not save screenshots or raw screen images.
- DeepSeek receives text context only unless the user explicitly changes the product design later.
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
- Before changing capture or always-on-top window behavior, consider failure modes where the app cannot receive input, cannot dismiss an overlay, or prevents the user from switching apps.

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
- Keep the floating tutor window always above normal windows.
- Clicking outside the tutor window should not close it.
- `Command + W` closes the tutor window.
- `Esc` cancels screenshot capture, but should not accidentally close the tutor window.

## Core User Flow

1. User presses `Shift + Command + O`.
2. TutorClip shows a fullscreen capture overlay.
3. User selects a region.
4. TutorClip captures the region in memory.
5. TutorClip runs local OCR.
6. TutorClip opens the floating tutor window.
7. Left side shows the current question text by default, with a screenshot tab available.
8. Right side shows SAT Tutor chat.
9. User can ask questions or use quick actions.
10. DeepSeek streams a Chinese explanation.
11. Closing the window discards the screenshot.
12. OCR, chat, and learning metadata are saved only if history is enabled.

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

For Math:

- Extract given information.
- Identify the concept tested.
- Solve step by step.
- Explain common traps.
- Give the final answer.

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
- AppKit for menu bar, floating panels, capture overlay, shortcut handling, and native text selection behavior.
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
- `DeepSeekClient`
- `PromptBuilder`
- `HistoryStore`
- `SettingsStore`
- `ConfigLoader`

Avoid mixing UI code, network code, persistence, OCR, and prompt construction in the same type.

`OCRRequestLifecycle` owns cancellation and session identity checks for in-memory screenshot OCR. Replacing or closing a tutor session must prevent an older OCR result from mutating the current window.

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
