# Help Sheet Sticky Letter Plan

Goal: Remember the last letter section a player opened in the Need Help sheet. When the sheet is reopened, automatically expand and scroll to that letter so players don’t have to re-scroll each time.

## Desired Behavior
- When the user taps a letter section in the Need Help sheet, store that letter (e.g., “B”).
- On next presentation of the sheet, auto-expand that letter and scroll it into view.
- If no letter was previously tapped, default to current behavior (no auto-scroll).

## Data/State
- Add `@State private var lastHelpLetter: String?` in `LlamaMascotContentView`.
- Pass the remembered letter into `helpSheetContent`.
- Within the help view, maintain an `@State var selectedLetter: String?` seeded from `lastHelpLetter`.
- Use a `ScrollViewReader` to scroll to the matching section when the sheet appears and `selectedLetter` is set.

## UI/Logic Changes
- Assign stable `id` to each letter section in the help list (e.g., `Section { ... }.id(key)`).
- On letter tap/expand, update both local `selectedLetter` and the parent `lastHelpLetter`.
- On sheet appear, if `selectedLetter` is not nil, `withAnimation { proxy.scrollTo(selectedLetter, anchor: .top) }` and mark the section expanded.

## Integration Steps
1) Add `lastHelpLetter` state to `LlamaMascotContentView`.
2) Update `helpSheetContent` signature to accept/set the remembered letter and expose a callback to store updates back to parent.
3) Wrap the help sections in a `ScrollViewReader`, give sections `.id(letter)`, and on appear scroll to `selectedLetter` if present; set `expandedHelpSections` to include that letter.
4) On letter tap, update `selectedLetter` and call back to set `lastHelpLetter`.
5) Reset `selectedLetter`/`lastHelpLetter` when the sheet is dismissed if desired (or keep for entire session).

## Testing
- Open Need Help, tap a letter; close and reopen: the same letter auto-expands and scrolls into view.
- Verify no regressions when no letter was previously selected.
- Test with multiple letters and with long lists to ensure scrollTo works correctly.***
