# Candidate Selection Flow (20 Questions)

This describes how the app updates its remaining candidates each time a question is answered (`ANNGameViewModel` in `20 Questions/ContentView.swift:13`).

1) **Record the answer**  
   - `answerCurrentQuestion` (`20 Questions/ContentView.swift:49`) saves the answer in `answers[q.id]` and marks the question as asked.

2) **Re-rank all animals** (`rerankAnimals`)  
   - Start every animal’s score at 0.  
   - For each answered question (`20 Questions/ContentView.swift:129`):  
     a. Map the answer to a base weight (`answerWeights` from `20 Questions/animals_ann.json`, e.g., YES=4, NO=-4).  
     b. Multiply by any per-question importance (`importance` in `20 Questions/ContentView.swift:237`, e.g., `is_venomous` ×3, `has_feathers` ×2, `is_bigger_than_car` ×2).  
     c. Look up the matrix weight for each animal on that question (`weights[animalId][questionId]` in `ANNDataStore`, `20 Questions/LLMScaffolding.swift:61`). If it’s zero, skip.  
     d. If the sign of the answer weight agrees with the sign of the matrix cell, add the (scaled) magnitude to that animal’s score; otherwise subtract it.  
   - If an answer is “Maybe/Not sure,” apply a small “unknown nudge” (`applyUnknownNudge` in `20 Questions/ContentView.swift:172`): add or subtract 1 based on the sign of the matrix weight.

3) **Keep only the top candidates**  
   - Sort animals by score (descending) and keep the top `topKForQuestionSelection` (currently 8).  
   - Expose these as `remainingAnimals` and `debugRemainingNames`.

4) **Advance the game state** (`runStep`)  
   - If only one animal remains, move to a guess.  
   - If the max question count is reached, guess the top remaining animal.  
   - Otherwise choose the next question with `chooseNextQuestion`.  
   - Logic lives in `20 Questions/ContentView.swift:99`.

5) **Choose the next question** (`chooseNextQuestion`)  
   - Consider only unasked questions and skip any blocked by dependencies (`shouldSkipQuestion` in `20 Questions/ContentView.swift:241`; e.g., skip `is_omnivore` if meat/plants were “No”; skip other class questions once one of mammal/bird/reptile/amphibian is “Yes”).  
   - For the current top candidates, simulate splitting them by each question’s matrix weights into YES/NO buckets (`20 Questions/ContentView.swift:185`).  
   - Compute entropy of the split (`entropy` in `20 Questions/ContentView.swift:208`); pick the question with the highest entropy (tie-breaker: better coverage).  
   - Avoid near-duplicates using a split signature of already asked questions (`splitSignature` in `20 Questions/ContentView.swift:213`).

6) **Learning after confirmation** (`finalizeGame`)  
   - When the user confirms the guess as correct, the model reinforces weights using the same per-question importance scaling (`20 Questions/ContentView.swift:79` and `learnFromGame` at `20 Questions/ContentView.swift:249`).  
   - If wrong, no weight changes are applied.

Result: After every answer, scores are re-computed for all animals using the weighted matrix and answer importance, top candidates are trimmed, and the next question is selected to best reduce uncertainty. This keeps the candidate list focused and favors high-signal questions like venomous/feathers/size.
