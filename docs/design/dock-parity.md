# Milestone 9 — Dock parity

Three gaps between Nexus and the real Dock, found by using it.

---

## 1. The Trash row looks like the Trash

**Now:** an SF Symbol, one state, because reading `~/.Trash` needs Full Disk Access and Nexus is
denied it (D55).

**Change:** macOS ships both icons and they are not protected:

```
/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns      (empty)
/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FullTrashIcon.icns  (full)
```

Loaded with `NSImage(contentsOfFile:)`, SF Symbol `trash` as the fallback if a future macOS moves
them.

**Full/empty without Full Disk Access.** `readdir` is blocked, but `stat` is not — measured on
this machine from inside Nexus:

```
contentsOfDirectory(~/.Trash)     -> nil          (denied)
stat(~/.Trash)                    -> ok, nlink=44 (42 items + 2)
stat(~/.Trash/.DS_Store)          -> ok           (exists)
stat(~/.Trash/definitely-not-there) -> fails      (so it is a real answer, not a blanket yes)
```

On APFS a directory's `st_nlink` is `2 + entry count`, files included — verified against a scratch
directory: empty `nlink=2`, one file `3`, two files `4`.

```
entries      = max(0, nlink - 2)
housekeeping = stat(.DS_Store) exists ? 1 : 0  +  stat(.localized) exists ? 1 : 0
isEmpty      = entries - housekeeping <= 0
```

The housekeeping subtraction is the whole point: Finder recreates `.DS_Store` the moment the Trash
window is opened, so counting it would leave the full icon showing over an empty Trash forever.

Sampled on the same user event as the window counts — the pointer entering the sidebar — plus once
at start and after an Empty Trash. `stat` is two syscalls, no permission, no polling.

## 2. Dragging rearranges live, like the Dock

**Now:** the row you drag stays put, nothing moves, and the reorder only appears when you let go —
so a drop that worked looks like a drop that failed.

**Change:** while a drag is in flight the sidebar shows a *preview order* that is not written to
the configuration until the drop lands.

```
beginDrag(id)            dragged row drops to 35% opacity
dragMoved(over:at:)      the middle of `target` offers a group; either end puts `id` beside it (D103)
endDrag(commit:)         commit -> configuration; cancel -> preview cleared, rows animate back
```

`SidebarViewModel` gains `draggingIdentifier` and a transient `previewOrder`, and `pinned` is
ordered by the preview whenever one exists. Rows are keyed by bundle identifier already, so
SwiftUI animates the moves by itself once the array changes inside `withAnimation`; Reduce Motion
turns the animation off and keeps the reordering.

The drag callbacks come from the same `NSView` that already owns mouse-down (D56):
`draggingUpdated` drives `dragMoved`, `draggingSession(_:endedAt:operation:)` drives `endDrag`.
Only already-pinned rows get a preview — dragging a *running* application into the pinned section
still commits on drop, because there is no slot to preview it in.

## 3. The window list is in the right-click menu

**Now:** right-click → Show Windows → a flyout. Two steps to reach the second window of an
application, which the Dock does in one.

**Change:** the context menu opens with the application's windows, the frontmost one ticked,
exactly like the Dock:

```
✓ Claude
  Design
  ────────
  Open
  Show All Windows
  Pin
  …
```

Clicking one raises that window (`WindowService.activate(_:)`, which already raises before
activating). The flyout stays — it is the one with thumbnails — under its Dock name, **Show All
Windows**.

Titles need Accessibility, and an `NSMenu` is built synchronously, so the list comes from a
main-actor cache filled when the pointer enters a row. A row whose windows have not arrived yet
(no permission, first hover, an application that answers slowly) simply shows no window section —
the menu is never blocked waiting for AX.

Without Accessibility there is no window section at all, which matches the existing rule: window
*counts* are permission-free, window *titles* are not (D5).

---

## Decisions to record

- **D58.** Supersedes D55: full/empty Trash state is back, via `stat` link counts rather than
  `readdir`, so no Full Disk Access is involved. Housekeeping files are subtracted by name.
- **D59.** Drag reordering shows a live preview order held in the view model, committed on drop
  and dropped on cancel. The configuration is written once, at the end — a drag that is cancelled
  or dropped outside must not leave a reordered dock behind.
- **D60.** The window list moves into the context menu, with the flyout kept as "Show All
  Windows". The menu list is built from a hover-warmed cache and degrades to nothing rather than
  blocking on AX.

## Tests

- `TrashService.isEmpty` against scratch directories: empty, one file, one file plus `.DS_Store`,
  `.DS_Store` alone.
- Preview order: `dragMoved` reorders without touching the configuration; commit writes it; cancel
  restores the stored order.
- The menu builder returns the windows section only when the cache has entries, and marks the
  frontmost window.
