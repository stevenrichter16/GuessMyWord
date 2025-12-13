# Fun Facts Page Plan

Goal: Add a dedicated Fun Facts page reachable from the side menu that lists every animal with available fun facts. Each animal appears as its own section with an avatar header and its facts beneath it.

## Data & Assets
- Source facts from `fun_facts.json` (already bundled). Build a lookup `[String: [String]]` keyed by animal id/name.
- Determine the set of animals to show: all keys present in `fun_facts.json`, optionally intersected with `animals_ann.json` for display names.
- Avatars: reuse existing asset naming (same helper logic as `funFactAssetName` in `LlamaMascotContentView`), with graceful fallback to a generic icon if missing.

## UI/UX
- Add a side-menu entry: “Fun Facts” that navigates/presents the new page.
- Fun Facts page: `NavigationStack` with a `List`/`ScrollView` using `Section` per animal.
  - Section header: avatar (40–60pt) + animal name.
  - Section body: list of fact rows (`Text`, multiline, readable spacing).
- Sort animals alphabetically for predictability.
- Empty/error states: show a simple message if no facts are available.

## State & Loading
- Load and cache fun facts once (e.g., `@StateObject` loader or a simple static cache).
- Map animal ids to display names (prefer `animals_ann.json` names; fallback to capitalized key).

## Accessibility
- Section headers and fact rows should have descriptive accessibility labels (e.g., “Fun fact about <animal>”).
- Ensure images have labels or are hidden from accessibility when decorative.

## Implementation Steps
1) Create a fun-facts loader helper (e.g., `FunFactsStore`) that reads `fun_facts.json`, exposes `animals: [FunFactsAnimal]` where each has `id`, `name`, `facts`, and `assetName`.
2) Extract/Share asset-name resolution: reuse existing logic from `funFactAssetName` (move to a shared helper if needed) to find matching image names.
3) Build `FunFactsView`: a SwiftUI view that displays the loaded animals in a sorted list of `Section`s with avatar headers and fact rows; include empty/error fallback UI.
4) Wire navigation: add a “Fun Facts” entry in `SideMenuView` to present/push `FunFactsView` (e.g., via sheet or navigation link state in `LlamaMascotContentView`).
5) Test: verify the page loads, bat/chimpanzee/cheetah/porcupine/monkey images render, facts display correctly, and side-menu navigation works; check accessibility labels/VoiceOver reads well.
