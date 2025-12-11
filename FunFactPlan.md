# Fun Fact Card Plan (LlamaMascotContentView)

Feature: Display a fun fact card below the Restart button. Each turn, show a fun fact about one of the animals in the game (random or context-aware). The card updates every turn.

## Scope
- Target view: `LlamaMascotContentView` (positioned below the Restart button).
- Content: A short fun fact tied to an animal in the dataset.
- Update cadence: On every turn change (question answered, guess confirmed, restart).

## Data
- Source fun facts from a JSON or dictionary keyed by `AnimalId` (e.g., `funFacts[AnimalId] = [String]`).
- Fallback: if no fact for a given animal, use a generic fact or skip.
- Optional variety: choose randomly from multiple facts per animal.

## UI/UX
- Card styling consistent with existing cards: rounded corners, subtle shadow, padding, theme colors.
- Include animal name (or emoji/icon if available) plus the fact text.
- Keep text short (1–2 lines) and readable; support multiline if needed.
- Optional affordance: a “refresh” button/icon to cycle facts without advancing turns.

## State
- `@State var funFact: (animal: Animal, text: String)?`
- Optional: `@State var funFactSeed` to force regeneration on demand.

## Logic
- On turn change (after `answerCurrentQuestion`/`finalizeGame`/`restart`), pick a fact:
  1) Determine candidate animals (e.g., from `remainingAnimals`, `currentGuess`, or allAnimals).
  2) Choose one animal (random or weighted).
  3) Fetch a fact for that animal; if none, retry or fallback.
  4) Set `funFact` state.
- On restart, refresh to a new fact.
- Optional: expose a “refresh fact” button that triggers regeneration.

## Integration Steps
1) Add fun fact data structure (in code or JSON resource) accessible to `LlamaMascotContentView` (or `ANNGameViewModel`).
2) Add fun fact state to `LlamaMascotContentView` and a helper to generate a fact based on the current game state.
3) Hook the generator to lifecycle events: after answering a question, after finalizing a guess, and on restart.
4) Insert the fun fact card view below the Restart button with matching styling and optional refresh icon.
5) Handle empty state gracefully (hide card if no fact found).

## Accessibility
- Provide an accessibility label like “Fun fact about <animal>” and read the fact text.
- Ensure the card is reachable/focusable and respects dynamic type.

## Performance
- Keep facts in-memory; no network calls.
- Random selection should be lightweight.
