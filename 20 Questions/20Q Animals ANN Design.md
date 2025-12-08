# 20Q Animals Game - ANN Design (Patent Inspired)

Design and specification for an on-device, animal-only 20 Questions game that mimics the original 20Q patent's ANN-style guessing and learning loop. Intended as a hand-off for implementation in Swift/SwiftUI.

---

## 1) Concept Overview
- Knowledge lives in a weights matrix: `questions x animals`.
- Two modes, refreshed every turn:
  - **Answers -> Animals:** score and rank animals based on user answers and matrix weights.
  - **Animals -> Questions:** from top-ranked animals, pick the question that best splits them.
- Learning = incremental weight adjustments after a confirmed correct guess.
- No hard filtering; rankings degrade gracefully when answers are noisy or subjective.

---

## 2) Domain: Animals and Questions

### Animals
- Fixed set of 100 animals (see `animals_20q.csv` for the full list). Each has:
  - `id` (machine, e.g. `lion`)
  - `name` (display, e.g. `Lion`)

### Questions / Attributes
- Boolean-ish attributes phrased as friendly questions, e.g.:
  - `is_mammal` - "Is it a mammal?"
  - `is_pet` - "Is it commonly kept as a household pet?"
  - `is_wild` - "Is it mostly found in the wild?"
  - `is_large` - "Is it larger than an average adult human?"
  - `is_bird` - "Is it a bird?"
  - `is_reptile` - "Is it a reptile?"
  - `is_fish` - "Is it a fish?"
  - `is_amphibian` - "Is it an amphibian?"
  - `has_stripes` - "Does it have obvious stripes on its body?"
  - `has_spots` - "Does it have noticeable spots on its body?"
  - `has_shell` - "Does it have a hard shell on its body?"
  - `has_fur_or_hair` - "Does it have fur or hair?"
  - `has_hooves` - "Does it have hooves instead of paws or claws?"
  - `can_fly` - "Can it naturally fly?"
  - `lives_in_water` - "Does it live mostly in water?"
  - `lives_on_farm` - "Is it commonly found on farms?"
  - `lives_in_forest_or_jungle` - "Is it mainly found in forests or jungles?"
  - `lives_in_grassland_or_savanna` - "Is it mainly found in open grasslands or savannas?"
  - `lives_in_desert` - "Is it adapted to live in the desert?"
  - `lives_in_cold_climate` - "Is it typically found in cold or icy climates?"
  - `lives_in_groups` - "Does it usually live in groups, herds, packs, or flocks?"
  - `is_domesticated` - "Has it been domesticated by humans?"
  - `is_nocturnal` - "Is it mostly active at night?"
- Expandable with more broad, human-answerable traits (avoid hyper-specific single-animal traits).

---

## 3) ANN Data Model

### Conceptual Matrix
- `weights[animalId][questionId] = Int` (negative, positive, or zero).
  - Positive weight: a Yes-ish answer increases this animal's score.
  - Negative weight: a No-ish answer increases this animal's score.
  - Near zero: question is not very informative for that animal.
- Answer categories map to numeric values:
  - YES / PROBABLY / USUALLY -> positive
  - NO / PROBABLY_NOT / RARELY -> negative
  - UNKNOWN / IRRELEVANT -> 0

### Canonical JSON Config (`animals_ann.json`)
```json
{
  "version": 1,
  "answerWeights": { "YES": 4, "NO": -4, "UNKNOWN": 0 },
  "animals": [
    { "id": "dog", "name": "Dog" },
    { "id": "cat", "name": "Cat" }
  ],
  "questions": [
    { "id": "is_mammal", "text": "Is it a mammal?" },
    { "id": "is_pet", "text": "Is it commonly kept as a household pet?" }
  ],
  "weights": {
    "dog": { "is_mammal": 10, "is_pet": 12, "lives_in_water": -8 },
    "cat": { "is_mammal": 10, "is_pet": 11 },
    "lion": { "is_mammal": 10, "is_pet": -8, "is_large": 8 }
  }
}
```
- Missing weights imply 0; every animalId present; questionId keys may be sparse.
- Initial seeding can come from the attribute matrix (e.g., +10 for known yes, -10 for known no) and will adapt via learning.

### Swift Codable Types
```swift
typealias AnimalId = String
typealias QuestionId = String

struct AnimalsANNConfig: Codable {
    let version: Int
    let answerWeights: [String: Int]
    let animals: [AnimalDef]
    let questions: [QuestionDef]
    let weights: [AnimalId: [QuestionId: Int]]
}

struct AnimalDef: Codable { let id: AnimalId; let name: String }
struct QuestionDef: Codable { let id: QuestionId; let text: String }
```

---

## 4) ANNDataStore (Swift)
- Holds the config and mutable weights; supports safe read/write and optional persistence.

```swift
final class ANNDataStore {
    let config: AnimalsANNConfig
    private(set) var weights: [AnimalId: [QuestionId: Int]]

    init(config: AnimalsANNConfig) {
        self.config = config
        self.weights = config.weights
    }

    convenience init?(resourceName: String = "animals_ann",
                      bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(AnimalsANNConfig.self, from: data)
            self.init(config: config)
        } catch {
            print("ANNDataStore load failed:", error)
            return nil
        }
    }

    func weight(for animalId: AnimalId, questionId: QuestionId) -> Int {
        weights[animalId]?[questionId] ?? 0
    }

    func setWeight(_ newValue: Int, for animalId: AnimalId, questionId: QuestionId) {
        var perAnimal = weights[animalId] ?? [:]
        perAnimal[questionId] = newValue
        weights[animalId] = perAnimal
    }

    func addToWeight(_ delta: Int, for animalId: AnimalId, questionId: QuestionId) {
        let current = weight(for: animalId, questionId: questionId)
        setWeight(current + delta, for: animalId, questionId: questionId)
    }
}
```
- Optional: `save(to:)` for persisting learned weights to Documents.

---

## 5) Game Logic With ANN

### Answer Representation
```swift
enum Answer: Int { case yes = 1, no = 0, unknown = -1 }

private func answerWeightKey(for answer: Answer) -> String? {
    switch answer { case .yes: return "YES"; case .no: return "NO"; case .unknown: return "UNKNOWN" }
}
```

### Ranking Animals (Mode 1: Answers -> Animals)
- For each answer:
  - Map to `answerWeight`; skip zeros.
  - For every animal, get `cellWeight`.
  - If signs agree, add `abs(answerWeight)` to that animal's score; else subtract it.
- Sort animals by score descending; keep top `k` (e.g., 8) as active candidates.

### Choosing Next Question (Mode 2: Animals -> Questions)
- Margin heuristic on the top candidates:
  - For each unused question, count how many candidates have `weight > 0` (yes) vs `weight < 0` (no).
  - Skip if fewer than two candidates have a non-zero weight.
  - Pick question with smallest `abs(yesCount - noCount)` (best balance).
- If none qualify, fall back to the current top guess.

### Learning (After Correct Guess)
- For each answered question:
  - Map answer to `delta` via `answerWeights`.
  - Skip `unknown`.
  - `annStore.addToWeight(delta, for: correctAnimalId, questionId: qId)`.
- Optionally clamp to min/max and/or penalize disagreeing weights on other animals later.

---

## 6) SwiftUI GameViewModel Using ANN
- State exposed: `currentQuestion`, `currentGuess`, `isFinished`, `debugRemainingNames`.
- Internal:
  - `annStore`, `allAnimals`, `allQuestions`
  - `remainingAnimals`, `answers`, `askedQuestions`
  - constants: `maxQuestions = 20`, `topKForQuestionSelection = 8`
- Loop (`runStep`):
  1. If one animal remains, set `currentGuess`, finish.
  2. If `answers.count >= maxQuestions`, guess best remaining, finish.
  3. Else `chooseNextQuestion` -> set `currentQuestion`; if none, guess best remaining.
- Public API:
  - `answerCurrentQuestion(_:)` -> record answer, rerank animals, runStep.
  - `restart()` -> reset state and runStep.
  - `finalizeGame(correct:)` -> when correct and `currentGuess` present, call `learnFromGame`.

---

## 7) SwiftUI View Example
- Simple UI that:
  - Shows current question with Yes / No / Not sure buttons.
  - When guessing, shows animal name with Correct / Wrong buttons and Restart.
  - Debug text showing current top candidates.

```swift
struct GameView: View {
    @StateObject private var viewModel = GameViewModel()!

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let q = viewModel.currentQuestion, !viewModel.isFinished {
                    Text("Think of an animal...").font(.headline)
                    Text(q.text).font(.title2).multilineTextAlignment(.center)
                    HStack {
                        Button("Yes") { viewModel.answerCurrentQuestion(.yes) }.buttonStyle(.borderedProminent)
                        Button("No") { viewModel.answerCurrentQuestion(.no) }.buttonStyle(.bordered)
                        Button("Not sure") { viewModel.answerCurrentQuestion(.unknown) }.buttonStyle(.bordered)
                    }
                } else if let guess = viewModel.currentGuess {
                    Text("Your animal is...").font(.headline)
                    Text(guess.name).font(.largeTitle).bold()
                    HStack {
                        Button("Correct") { viewModel.finalizeGame(correct: true) }.buttonStyle(.borderedProminent)
                        Button("Wrong") { viewModel.finalizeGame(correct: false) }.buttonStyle(.bordered)
                    }
                    Button("Play again") { viewModel.restart() }.buttonStyle(.bordered)
                } else {
                    Text("I'm out of ideas :)")
                    Button("Play again") { viewModel.restart() }.buttonStyle(.borderedProminent)
                }
                VStack(alignment: .leading) {
                    Text("Top animals (debug):").font(.caption)
                    Text(viewModel.debugRemainingNames.joined(separator: ", ")).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("20 Questions: Animals")
        }
    }
}
```

---

## 8) Notes and Extensions
- Persist learned weights between sessions to accumulate knowledge.
- Adjust answerWeight mappings to support richer answers (probably, usually, rarely).
- Add clamping or decay to avoid runaway weights.
- Swap the margin heuristic for entropy/info gain later if desired; keep ANN scoring for animal ranking.
