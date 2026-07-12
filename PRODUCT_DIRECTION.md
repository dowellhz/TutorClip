# TutorClip Product Direction: Adaptive SAT Tutor

Status: implemented direction; full permission-dependent manual verification remains tracked in `VERIFY.md`.

## Product Position

TutorClip is becoming a normal macOS learning application rather than a utility
that exists only after screenshot OCR. Its promise is:

> When the student opens TutorClip, it presents the most valuable next SAT
> question, learns from the response, and uses as little practice as necessary
> to establish durable mastery.

Screenshot OCR remains a fast way to bring a real question into the same tutor
and learning system.

## Window And Application Model

- TutorClip has a Dock icon, menu bar item, and standard main window.
- Normal launch opens the main window to Today Practice.
- OCR and generated practice appear in the same main window.
- The main window is never permanently floating or always on top.
- Completing a screenshot selection activates and fronts TutorClip once.
- If the student later selects another app, TutorClip moves behind it normally.
- OCR completion updates the window without stealing focus again.
- `Command + W` closes the window but leaves the app and global shortcut active.
- Clicking the Dock icon restores the main window; `Command + Q` quits.
- Settings can remain a separate normal macOS window. History, Knowledge Map,
  Vocabulary, Today Practice, and the current question belong in the main
  application structure.

## Main Window Information Architecture

The main window should provide stable destinations for:

- Today Practice
- Current Question
- Knowledge Map
- History
- Vocabulary
- Settings

Today Practice should lead with a question or a clear actionable state, not a
dashboard that forces the student to plan the lesson. Small progress and session
context may support the question without competing with it.

## Screenshot Session Lifetime

A screenshot is private, in-memory state owned by one active OCR session. It is
destroyed when the student:

- replaces it with another question;
- leaves that OCR session;
- opens a saved historical session; or
- closes the main window or quits TutorClip.

Returning to history can restore compliant OCR text, structured OCR metadata,
conversation, and learning data, but never the screenshot.

## Teacher-Style Question Selection

Question choice is guided randomization, not uniform random selection. The
teaching scheduler considers:

1. prerequisite knowledge blocking later work;
2. review that is due or likely to be forgotten;
3. weaknesses exposed by recent OCR questions;
4. points currently being learned or awaiting verification;
5. points not yet sampled;
6. transfer checks for apparently mastered knowledge; and
7. pacing, including recovery after difficult questions and avoidance of
   repetitive near-duplicates.

Every selected question has a teaching purpose: diagnostic, instruction,
guided recovery, verification, consolidation, transfer, or maintenance.

## Mastery Evidence

The current fixed requirement of four independent correct answers is retired.
Mastery decisions use evidence quality rather than a universal count.

Evidence includes:

- correctness;
- question difficulty;
- whether help or the answer was revealed;
- variation across wording, contexts, and reasoning demands;
- time separation and retention;
- error type; and
- question validity and answer confidence.

When a question maps to several knowledge points, the first validated target is
the primary full-strength signal. Additional associated points receive weak
diagnostic weight and cannot independently grant mastery.

Expected behavior:

- A genuinely simple point can pass its initial diagnostic after one strong,
  independent response.
- An ordinary point normally needs independent evidence in varied forms.
- A complex point needs evidence at suitable foundation, application, and/or
  transfer levels.
- A correct response after a hint helps learning but is not independent mastery
  evidence.
- An ambiguous or failed-validation question contributes no mastery evidence.
- A wrong response does not erase all prior evidence. Concept gaps, careless
  mistakes, reading errors, and language barriers lead to different actions.
- Previously stable knowledge can be restored with one successful due check
  instead of repeating an arbitrary quota.

Student-facing states are staged:

1. Unseen
2. Learning
3. Initially Mastered
4. Stably Mastered
5. Due for Review

## Knowledge Graph

The knowledge model must become more than a hierarchy. In addition to stable,
versioned knowledge-point IDs, it needs relationships for:

- prerequisites;
- easily confused concepts;
- composite skills used together; and
- difficulty or progression levels.

Reading and Writing and Math both need complete coverage before the product says
the whole SAT graph is mastered. Catalog version upgrades must preserve existing
evidence where IDs and meanings remain compatible.

One question can provide strong evidence for its primary target and weaker
diagnostic signals for secondary points. It must not mark every associated point
correct or incorrect equally.

## New Student And Ongoing Practice

A new student starts with a short, broad diagnostic. The goal is to establish a
useful starting profile quickly and let obviously easy material pass without
repetitive drilling.

Daily practice should have a natural stopping point. When scheduled learning is
complete, TutorClip says so and offers optional challenge, simulation, or free
practice. Stable knowledge moves to increasingly infrequent maintenance checks;
"all mastered" is a maintenance phase, not an endless feed or permanent claim.
The implemented default finishes the initial broad diagnostic after eight valid
responses and regular required practice after five responses in a day.

## AI Question Contract And Failure States

Generated practice must identify, in a structured form:

- primary knowledge point and prerequisites;
- teaching purpose and target difficulty;
- question and answer choices;
- one correct answer and its reasoning basis;
- the misconception represented by each distractor; and
- the explanation plan.

Generated questions are validated before they can affect mastery. In particular,
the system should reject insufficient context, multiple defensible answers,
incorrect math, malformed choices, and near-duplicate variants.

The main window must remain useful and explicit when the API key is missing,
networking fails, generation is slow, or validation rejects a question. It must
offer setup or recovery actions rather than showing an empty page or silently
retrying forever.

## Persistence And Privacy Controls

Learning progress and detailed question/conversation history are separate user
choices:

- Learning progress includes answer evidence, mastery state, review scheduling,
  study status, and vocabulary cards.
- Detailed history includes OCR text, structured OCR metadata, generated or OCR
  question text, and conversations.

First-run UI must explain these controls before persistence. A student may keep
abstract learning progress without retaining detailed questions or chats.
Answer evidence is saved when the answer is committed; it must not depend on the
student closing a window. Neither category may contain screenshots, raw images,
or API keys.

## Implementation Boundaries

- The main window presents navigation and session state.
- A teaching scheduler chooses the next objective, purpose, and difficulty.
- A mastery evidence owner records evidence and schedules review.
- A question generation and validation pipeline produces safe practice content.
- OCR lifecycle ownership continues to prevent stale results from mutating a
  replaced session.
- `AppCoordinator` orchestrates these owners; it does not contain teaching,
  persistence, prompt, OCR, or window internals.

## Migration Notes

The normal-app migration is implemented: TutorClip now has a Dock presence,
reuses one ordinary opaque main window, and uses evidence quality instead of a
fixed four-correct threshold. Screenshot cancellation, OCR lifecycle ownership,
and the separate privacy boundaries for detailed history and abstract learning
evidence remain invariants for future changes.
