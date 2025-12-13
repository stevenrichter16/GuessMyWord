# Enhanced Fun Fact Picker Plan

Goal: Avoid repeating the same fun facts across consecutive games in a session by keeping picker state alive beyond a single game. Persistence is in-memory only for now (reset on app relaunch); later we can serialize to UserDefaults.

## Desired Behavior
- Track which facts have been shown per animal; avoid repeats until that animal’s list is exhausted, then reset that animal’s pool.
- Optionally keep a short recency buffer to avoid immediate repeats across animals.
- Picker state survives multiple game restarts within the same app session (not persisted across relaunch yet).

## Data Structures
- `FunFactPicker` (ObservableObject or plain class held in `@StateObject`):
  - `facts: [String: [String]]` loaded from `fun_facts.json`.
  - `usedByAnimal: [String: Set<Int>]` tracking which indices have been used per animal.
  - `recent: [FactKey]` (optional) where `FactKey = (animalId: String, index: Int)` to enforce a recency window (e.g., last 5).
  - `recencyLimit: Int` constant.

## API
- `nextFact(preferredAnimals: [String]?) -> (animal: String, fact: String)?`
  1) Candidate animal ids are all keys present in `facts`.
  2) Choose an animal by sampling those with unused facts; fall back to those needing reset if all are exhausted.
  3) Pick an index from that animal’s available facts, excluding `used` and optionally excluding `recent`.
  4) If none available, clear that animal’s used set (and remove its recency entries), then pick from its full range.
  5) Record the chosen index in `usedByAnimal[animal]` and push `(animal, index)` into `recent` (trimming to `recencyLimit`).
  6) Return the chosen pair.
- `resetAll()` to clear all usage (e.g., if user toggles a setting).
- `resetAnimal(_ id: String)` helper when an animal’s facts are exhausted.

## Integration Steps
1) Add `FunFactPicker` type and load `fun_facts.json` once into memory.
2) Instantiate `FunFactPicker` as a shared `@StateObject` in `LlamaMascotContentView` (or an ancestor) so it survives restarts within the session.
3) Update `generateFunFact()` to call `picker.nextFact()` without context-aware filtering.
4) On game restart, **do not** reset the picker; only reset when the app relaunches or via an explicit user action (not implemented yet).
5) Keep existing asset/name resolution for display; reuse the chosen animal id to derive the display name.

## Future (not in scope now)
- Persist `usedByAnimal` + `recent` to UserDefaults with a timestamp for aging.
- Add a user control to clear fun fact history.
