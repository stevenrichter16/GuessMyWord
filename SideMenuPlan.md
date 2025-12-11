# Side Menu Plan (Minimal Overlay)

**Goal:** Add a small, non-intrusive options entry point that opens a compact side menu (30% screen width) with two items: Developer Mode and Feedback.

## Entry Point
- Small circular button (32–36pt) in the top-right, floating above content with a subtle shadow and optional thin stroke.
- Icon: three dots or sliders. Accessibility label: “More options”.
- Tap to toggle menu; consider a right-edge swipe to open.

## Menu Presentation
- Slide-in panel from the right; width ~30% of the screen, full height on phones. Rounded leading corners (16–20pt).
- Background dim: low-opacity scrim over main content; tap scrim to dismiss.
- Animation: 200–250ms ease-in-out slide; entry button can rotate or scale slightly on toggle.
- Lock underlying scroll when open.

## Menu Content (initial)
- Developer Mode
- Feedback
- (Placeholders for future items can be added later.)

## Layout & Styling
- Vertical list with consistent padding; use existing typography/color tokens.
- Minimal separators or subtle dividers if needed; avoid clutter.
- Keep destructive actions (none now) tinted red and at the bottom if added later.

## State & Behavior
- Track `isMenuOpen`. On open: animate menu + scrim; on close: reverse animations.
- Dismiss via: options button toggle, scrim tap, or back gesture.
- Maintain VoiceOver focus order; ensure the options button and each item have clear accessibility labels.

## Integration Notes
- Encapsulate the menu in its own view (e.g., `SideMenuView`) with bindings for open state and actions (Developer Mode, Feedback).
- Overlay the menu using a `ZStack` on the main screen; keep the button anchored top-right within safe areas.
