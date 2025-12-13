# Gallery Plan

Goal: Add a Gallery page accessible from the side menu that shows all animal avatars with names above them and allows copying an avatar to the clipboard.

## Data & Assets
- Source animals from `animals_ann.json` for consistent ids/names.
- Resolve avatar asset names using the existing fun fact asset resolver; show a placeholder if missing.

## UI/UX
- Side menu entry: “Gallery” presents a gallery view (modal or push).
- Gallery view: adaptive grid; each cell shows the animal name above a circular avatar.
- Empty state message if no avatars are available.
- Header shows total animal count.

## Copy Behavior
- Tap/long-press provides a copy action that places the avatar image on the clipboard (`UIPasteboard` with `UIImage`).
- Show a brief “Copied” toast after a successful copy.

## State & Structure
- `GalleryStore` (ObservableObject) loads animals and resolves assets, exposing `[GalleryItem]` with `id`, `name`, `assetName`.
- Handle missing assets gracefully with a placeholder image/icon.

## Implementation Steps
1) Create `GalleryStore` to load names/ids from `animals_ann.json` and resolve asset names.
2) Build `GalleryView` with an adaptive grid: name above avatar, copy action (tap/context menu), and “Copied” toast.
3) Add a “Gallery” entry in the side menu to present `GalleryView`.
4) Test: verify avatars render, names align, copy puts the image on the clipboard, toast appears, and empty state works.
