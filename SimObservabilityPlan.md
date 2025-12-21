## Simulation Observability Plan

### Goals
- Capture richer per-round telemetry in simulation runs to diagnose question quality, candidate narrowing, and error patterns.
- Persist logs locally as JSON for export/analysis (candidate rankings, entropy, timings, confusion signals).
- Keep the developer UI simple: run sims (1/10/20), view/save logs.

### Targets
1) **Raw per-question metrics**
   - Candidate set size before/after question.
   - Top-N candidates with scores/probabilities each turn.
   - Rank of true animal and final guess each turn.
   - Entropy/coverage of the asked question for current top-K.
   - Weight/score delta applied by the answer (if exposed).
   - Time per question (generation + answer).
   - Flag if question was “special/gated.”
2) **Game-level metrics**
   - Turns to guess; guess confidence (if available); margin top-1 vs top-2.
   - Did target leave top-K? When? Min/median/max rank over time.
   - Final candidate list and scores at guess time.
   - Contradictions injected and if they flipped outcome.
3) **Derived summaries per run**
   - Average entropy gain per question, average candidate reduction.
   - Questions that produced no narrowing.
   - Path of true animal rank.
4) **Export**
   - Save last run log (already present).
   - Save full report (already present).
   - Ensure JSON ordering for key fields.

### Plan
1) **Data model updates (GameSimulation.swift)**
   - Extend `SimulationQuestionLog`:
     - `candidateCountBefore/After`
     - `topCandidates: [(name, score/prob?)]`
     - `trueRankBefore/After`
     - `entropy`, `coverage`
     - `isSpecialQuestion`
     - `questionDurationMs` (if timing captured)
   - Extend `SimulationRoundLog`:
     - `turnsToGuess`
     - `guessConfidence` (if available)
     - `topCandidatesAtGuess`
     - `trueRankPath` (array of ranks per turn)
     - `leftTopKAtTurn` (optional)
     - `contradictionsApplied`
     - `candidateCountPath`
     - `finalScores` (if accessible)
   - Keep JSON key ordering for `target`, `guess`, `wasCorrect`.

2) **Capture metrics in ANNSession (simulation path)**
   - Track rankedAnimals before/after each question to compute:
     - candidate counts, true rank path, top-N snapshot, coverage/entropy.
   - Mark questions as special if in `specialQuestions`.
   - Record per-question timing (wrap nextQuestion + autoAnswer + recordAnswer).

3) **Integration points**
   - In `GameSimulator.playSingle`:
     - Collect per-question logs with the new fields.
     - Build per-run summary fields (turnsToGuess, rank path, candidate counts, contradictions applied).
   - Ensure `SimulationRun` carries the enriched `SimulationRoundLog`.

4) **Developer UI**
   - Existing buttons (1/10/20 sims, noisy) remain.
   - Export buttons already save last log and full report; ensure the report includes the enriched fields.
   - Optionally add a “Show log location” label (Documents path) for easier retrieval.

5) **Testing/Validation**
   - Run a 1-sim and inspect JSON for all new fields.
   - Verify ordering of `target/guess/wasCorrect`.
   - Spot-check special question gating still works.
   - Confirm no crashes if probabilities/scores are missing (nil-safe defaults).

6) **Follow-ups (optional)**
   - Add aggregation view (average entropy gain, hardest animals, confusion pairs).
   - Add toggle to include/exclude top-N candidate snapshots for log size control.

### Expected Outcomes
- **Surface weak/redundant questions:** Low entropy, zero coverage, or no narrowing metrics flag prompts to rewrite, reorder, or drop.
- **Data quality fixes:** Mismatches between “true” answers and dataset-derived answers expose labeling/schema issues to correct.
- **Hard animals & confusions:** Rank paths and top-N snapshots show which animals fall out of top-K or get confused; guides adding discriminative questions or adjusting weights for common confusers.
- **Validate gating/specials:** Confirm special questions fire when relevant; if rarely used or ineffective, adjust gating or weights.
- **Scoring/weight tuning:** Candidate score deltas and top-1 vs. top-2 margins indicate if answer weights are too weak/strong; informs weight scaling and top-K choices.
- **Efficiency tuning:** Turns-to-guess, entropy gain per turn, and time per question reveal slow convergence or premature guesses; supports changing max turns or early-guess policy.
- **Robustness checks:** Contradiction logs show resilience to misclicks; guide adding tolerance or follow-up questions.
- **Exportable evidence:** Per-run JSON enables offline analysis (confusion matrix, average entropy gain, hardest animals/questions) and tracking improvements over time.

### Simulating Realistic Users (beyond random noise)
- **Personas:** Define profiles (kid, casual, nature-nerd) with familiarity scores per animal, question-type confidence, base “unknown” and mistake rates.
- **Question difficulty:** Assign confidence tiers per question/animal or question/category (appearance easy; diet/behavior/habitat harder) to modulate unknown/mistake probabilities.
- **Confusion clusters:** Encode likely confusions (e.g., pelican/flamingo/duck; turtle/tortoise; hawk/falcon/eagle) and bias wrong answers toward cluster-consistent mistakes.
- **Inconsistency:** Inject occasional self-contradictions and correlated uncertainty (if unsure on one diet question, higher chance of unsure on related ones).
- **Animal familiarity tiers:** Tier animals; lower tiers increase unknown/mistake rates globally.
- **Behavior patterns:** Add sliders (yes-bias, unknown-bias, riskiness) to sample a persona’s answer style.
- **Scenario scripts:** Create a few plausible answer scripts per cluster and sample from them for synthetic but human-like transcripts.
