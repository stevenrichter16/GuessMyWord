# Guess-My-Word Game — Implementation Plan

## Goal
A single-mode game where the user thinks of a common item/object/animal and the on-device LLM asks up to 10 yes/no/maybe questions before making one guess with a brief rationale.

## Scope (what to ship)
- One screen SwiftUI experience: current question, answer buttons (Yes/No/Maybe/Not sure), turn counter, transcript, final guess + rationale, Restart.
- Constrained answer domain (100–200 common items across categories like kitchen, office, animals, foods, tools) to keep accuracy high.
- Basic guardrails: JSON-shaped LLM outputs, short questions (<80 chars), one question per turn, forced guess by turn 10.
- Optional: free-form hint input from the user mid-game that the LLM can parse to adjust its hypothesis.

## Architecture
- State model: `GameState` with `turn`, `maxTurns`, `transcript` (Q/A pairs), `phase` (`asking` | `guessing` | `finished`), `finalGuess`, `confidence`, `rationale`, `isBusy`.
- Message structs:
  - `QA` with `turn`, `question`, `answer`.
  - `LLMAskResponse { question: String }`.
  - `LLMGuessResponse { guess: String, confidence: Double, rationale: String }`.
- Prompt builder that composes system prompt + recent transcript (last N turns) + mode flag (`ask` vs `guess`) + optional hint + canonical item list.
- LLM client wrapper to send prompts to the local Foundation model, parse JSON, and retry if malformed.

## Prompting (starter)
- System prompt:
  - Role: 20-questions guesser.
  - Allowed domains: include canonical item list and category names; forbid abstract/proper nouns.
  - Rules: ask exactly one concise yes/no/maybe question per ask turn; avoid embedding guesses in questions; no multiple questions; keep under 80 chars.
  - Guess mode: return a single best guess, confidence 0–1, and one-sentence rationale.
- Output formats:
  - Ask mode: `{"question":"Is it electronic?"}`
  - Guess mode: `{"guess":"toaster","confidence":0.74,"rationale":"Electric, small, kitchen-only."}`
- On invalid output: in code, reprompt with a short “Please follow the JSON format.”

## UI Flow (SwiftUI)
- Header with instructions (“Think of a common item from these categories: …”).
- Turn counter and current question text.
- Answer buttons: Yes / No / Maybe / Not sure. Buttons disabled while waiting for LLM.
- Optional hint text field + “Send hint” button (feeding a free-form hint to the next prompt).
- Transcript list of past Q/A pairs (truncate to keep UI tidy; keep full history in state).
- Final guess card with guess, confidence %, and rationale; buttons for Correct / Incorrect to end or restart.
- Restart button to reset state and ask the first question.

## Game Loop
1) On start/restart: set `turn = 1`, phase `asking`, request first LLM question.
2) Display question; user taps answer; append QA to transcript.
3) If `turn < maxTurns` and not confident, request next question; else switch to guess mode.
4) In guess mode, show guess + rationale + confidence; user marks correct/incorrect.
5) If incorrect, optionally ask the LLM “what distinguishing question would have helped?” (static text acceptable for v1) and show a restart CTA.

## Safety/UX Guardrails
- Clamp question length; if too long or malformed, auto-respond “Not sure—please ask a different concise question.”
- Reject outputs that don’t parse; retry once before showing an error toast and letting the user retry.
- Keep tokens small: send only last ~6 Q/A pairs plus hint and categories.

## Testing Plan
- Manual: run through several categories; verify questions are concise, non-redundant, and guess appears by turn 10.
- Harness: script a simulator that picks a hidden item from the canonical list, answers truthfully, runs 100 games, and logs accuracy, average turns, and repeat-question rate.
- UI: snapshot basic states (initial, mid-game, guessed).

## Future (post-MVP)
- Adaptive learning: when wrong, capture true item and ask the LLM for a distinguishing question to enrich a local hint list.
- More domains toggled in settings; confidence meter visualization; lightweight analytics on success rate (privacy-respecting, local if possible).
