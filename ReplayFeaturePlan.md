# Replay Feature Plan

Goal: Add a replay experience on a new page that animates each question/answer sequence, shows candidate changes with avatars emerging/returning to an “All Animals” origin, and runs as a timed presentation (~3 seconds per question step).

## Behavior Overview
- Entry point: a new “Replay” page (modal or navigation push) that replays a completed round.
- Timeline per question:
  1) Show the “All Animals” circle.
  2) Show the question text with non-tappable Yes/No buttons.
  3) Animate the chosen answer button (brief expand/pulse).
  4) Animate candidate avatars emerging from the All Animals circle; gently float/hover.
  5) On next question, repeat steps 2–4. Candidates that drop out animate back into the All Animals circle; new top candidates emerge.
  6) Each question segment lasts ~3 seconds from question appearance to candidate transition.

## Data Requirements
- Access to the completed game transcript:
  - Questions asked (text, id/order).
  - User answers (Yes/No/Maybe).
  - Candidate sets after each step (top candidates list per question).
- Animal metadata:
  - Names and associated avatar asset names (reuse existing resolver).

## State & Models
- `ReplayStep`: contains question text, answer, and candidate ids for that step.
- `ReplayViewModel`:
  - Holds the ordered steps.
  - Tracks current step index, state of candidate avatars (current vs. next).
  - Drives a timer to advance every ~3 seconds.
  - Computes diff between current candidates and next candidates to animate “in” and “out.”

## UI/UX
- Layout:
  - Top: Title and a close/back control.
  - Center: “All Animals” circle anchor.
  - Question: text centered; below it two non-tappable Yes/No buttons; animate the chosen one per step.
  - Avatars: Positioned around the All Animals circle; gentle hover animation.
- Animations:
  - Answer button: scale/pulse for the chosen answer.
  - Candidates emerging: scale/opacity in from the All Animals circle outward; drifting hover.
  - Candidates dropping: scale/opacity out toward the All Animals circle.
  - Timing: orchestrated with a per-step timer (~3 seconds).
- Controls:
  - Optional: Play/Pause and Restart within replay; or auto-play only with a close.

## Implementation Steps
1) Data capture:
   - Ensure the game stores a per-question log (question text/id, user answer, candidate list after each answer).
   - Build a converter to map that log into `[ReplayStep]`.
2) View model:
   - Create `ReplayViewModel` with published `currentStepIndex`, `currentCandidates`, `nextCandidates`, and `isPlaying`.
   - Add a timer to auto-advance every ~3 seconds; allow manual restart/pause if desired.
   - Diff candidates between steps to know which to animate in/out.
3) Avatar mapping:
   - Map candidate ids to display names and avatar asset names using existing resolver; provide placeholders if missing.
4) UI:
   - Create `ReplayView`:
     - Show All Animals circle.
     - Show question text and disabled Yes/No buttons; animate chosen answer.
     - Render candidate avatars in a simple radial/stack layout around the circle; apply hover animation.
     - Animate in/out based on diffs when advancing steps.
   - Optionally add progress indicator (step X of N).
5) Entry point:
   - Add a way to launch Replay after a game finishes (button on result, or from a history list).
6) Timing & polish:
   - Use `withAnimation` sequences per step; adjust durations (e.g., 0.4s for answer pulse, 0.6s for candidate transitions).
   - Keep total per-step duration ~3 seconds, then auto-advance.

## Testing
- Verify replay runs through all steps with correct questions/answers.
- Confirm candidates animate correctly: new ones emerge; removed ones retreat.
- Check behavior with few candidates and many candidates.
- Ensure hover animation is subtle and doesn’t interfere with timing.
- Validate close/back exits cleanly and stops timers.
