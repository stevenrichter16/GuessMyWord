# “Need Help?” Slide-Up Plan (LlamaMascotContentView)

Feature: In the Llama mascot flow, show a “Need Help?” affordance on the active question card. Tapping it opens a slide-up sheet showing the current question as the title and, below, all animals with their inferred answer to that question. The content is dynamic—no per-question hardcoding.

## Scope
- Target view: `LlamaMascotContentView`.
- Trigger: text/button on the current question card.
- Presentation: bottom sheet/slide-up.
- Data: derived from `ANNDataStore` weights and current `AnimalsANNConfig`.

## UI Hook
- Add a small “Need Help?” button inside the question area of `LlamaMascotContentView` when a question is active.
- On tap: capture `currentQuestion.id` and present the sheet.

## State
- `@State var helpQuestionId: QuestionId?`
- `@State var isHelpSheetPresented: Bool`
- Optional derived state: `helpEntries: [(Animal, String)]` computed on-demand.

## Data Derivation
- Use `ANNDataStore` to read `weights[animalId][questionId]`.
- Map weight → label: `>0` = “Yes”, `<0` = “No”, `==0` = “Unknown/Not sure” (align with existing Answer semantics).
- Build an array `(Animal, String)` for all animals; sort for readability (e.g., Yes, No, Unknown, then alphabetically).
- Recompute when presenting so it reflects learned updates.

## Presentation
- On tap, set `helpQuestionId = currentQuestion.id`, compute entries, set `isHelpSheetPresented = true`.
- Present as a `.sheet` or custom slide-up:
  - Title: current question text.
  - Body: scrollable list of animals with their answer label.
  - Close affordance: swipe down or explicit close button.

## Styling & Layout
- Keep styling consistent with mascot UI: use existing typography and card colors.
- Consider a subtle divider between rows; avoid clutter.
- Support dark/light modes.

## Accessibility
- “Need Help?” button: accessibility label like “Show how animals answer this question.”
- Sheet content: VoiceOver-friendly ordering; ensure dismiss gesture or close button is reachable.

## Integration Steps (LlamaMascotContentView)
1) Add the “Need Help?” button to the question bubble when `currentQuestion` is non-nil.
2) Add `helpQuestionId` and `isHelpSheetPresented` state vars.
3) Implement a helper to compute `(Animal, String)` answers for a question using `viewModel`’s `annStore` access (or expose a helper on the view model).
4) Add a sheet/slide-up bound to `isHelpSheetPresented`, rendering the question title and the computed list.
5) Wire dismissal to swipe/close.

## UI Improvements (letters & entries)
- **Alphabet sections:** Group by first letter; make each section collapsible with a clear header (e.g., bold letter, chevron, subtle background or divider). Keep spacing generous for tap targets.
- **Sticky/anchored header (optional):** Consider a lightweight sticky header per section when scrolling, or an A–Z jump control on the right for long lists.
- **Entry styling:** Use a pill/tag for the answer label (Yes/No/Unknown) with tint colors, align text baselines, and apply consistent padding and rounded rectangles for rows.
- **Empty-state messaging:** If no data, show a friendly message and optional guidance.
- **Motion:** Animate expand/collapse with a short ease; rotate the chevron to indicate state.
- **Theming:** Match the mascot screen’s typography, corner radius, and shadows; respect dark/light modes.
