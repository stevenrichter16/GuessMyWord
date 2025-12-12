# Replay in 10 Seconds — Visualization Concept

A lightweight replay that summarizes each turn of the animal-guessing game in ~10 seconds. The replay animates the timeline of questions, your answers, and how the AI's confidence shifts.

## Core idea
- Present a compact timeline strip showing each turn as a card: **Question → Your answer → Confidence change**.
- Play the sequence automatically in ~10 seconds with simple motion (slide/fade) and a progress bar; allow pause/replay.
- At the end, display the final guess card with a short rationale.

## Interaction flow
1. **Start replay**: After a game ends, a "Replay in 10 seconds" button appears beside the final guess.
2. **Autoplay timeline**: Show all 20 turns; cards slide in at ~0.4–0.5 seconds each, yielding a ~10–12s total replay.
3. **Per-turn card content**:
   - Turn number and the asked question.
   - Player answer (Yes/No/Maybe/Not sure) with color-coded chip.
   - Confidence meter showing the AI's belief in its top pick before and after the answer (e.g., sparkline or bar growing/shrinking). Highlight delta with a green/red arrow.
4. **Selection glimpse**: A mini "Top 3" strip beneath the meter shows the leading animals with tiny icons; the leader subtly bumps forward when its score rises.
5. **Controls**: Tap to pause/resume; swipe to scrub through turns; close button to return to results.
6. **Finish**: Replay ends on the final guess card with confetti if the player marked it correct.

## Visualizing AI selection after each turn (feasible approach)
- **Data captured each turn**: ordered candidate list with confidence/score, chosen question, user answer.
- **UI representation**:
  - Horizontal bar trio for the top 3 animals, labeled with icons/names and their normalized scores.
  - Animate bar length changes per turn; use smooth spring animation to emphasize momentum.
  - If the leader changes, briefly spotlight the new leader (pulse or crown icon).
- **Why feasible**: The engine already ranks `remainingAnimals` and exposes scores; we can normalize top scores to 0–100 and animate updates with SwiftUI `withAnimation` on state changes. Timeline cards can reuse existing question/answer text and small SF Symbol animal icons to avoid new assets.

## Implementation sketch (SwiftUI)
- **Model**: Extend the game state to log `TurnSnapshot { turn, question, answer, topAnimals: [(name, score)], topGuessConfidence }` after each `answerCurrentQuestion`.
- **View**: New `ReplayTimelineView` that consumes the snapshot array and animates through it with a timer.
- **Controls**: `ReplayController` to play/pause and scrub; `ProgressView` for overall 10-second progress.
- **Animation**: Use `TimelineView` or `withAnimation(.easeInOut(duration: 0.4))` for card transitions and bar growth.
- **Performance**: Limit stored snapshots to max 12 turns; use lightweight shapes and gradients (no remote assets) to keep animations smooth.

## Nice-to-haves
- Toggle for "Auto-play" vs. manual scrubbing.
- Option to export a GIF of the replay for sharing.
- Debug overlay showing exact score deltas for QA testing.

## Decisions / assumptions (open questions answered)
- **Turns shown**: All 20 turns; timing compressed to ~0.4–0.5s per card for a ~10–12s total.
- **Data source**: Each turn logs `TurnSnapshot { turn, question, answer, topAnimalsPre: [(name, score)], topAnimalsPost: [(name, score)], timestamp }` in the view model immediately after `answerCurrentQuestion`. Scores use the existing ranking/weights normalized 0–100 per turn.
- **Confidence delta**: For the leader, delta = postScore - preScore; show arrow up/down/flat and bar length change. For top-3 strip, animate bar length changes from pre to post.
- **Icons**: Use the bundled animal PNGs when present; fallback to an SF Symbol (e.g., `pawprint.circle`) if missing. Keep one style per card; no mixed sets on the same row.
- **Reduce motion**: If reduce-motion is on, disable autoplay and animations; show a static, scrollable list with a manual “Next/Prev” stepper.
- **Controls**: Play/Pause button, close button, and a scrub bar (tap to jump, drag to scrub) with generous hit targets. ProgressView shows overall replay progress.
- **Missing data**: If snapshots are incomplete or empty, hide the replay entry point and show a brief message (“Replay unavailable for this game”) instead of a broken view.
