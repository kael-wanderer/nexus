# Design

One file per feature.

| | |
|---|---|
| [`mvp.md`](mvp.md) | The cross-cutting design, and the MVP surface: panels and focus (a sidebar that can never become key, a palette that deliberately activates), permissions as capabilities, the layout vocabulary, search, displays, accessibility. Everything else inherits from here. |
| [`dock-replacement.md`](dock-replacement.md) | Four sidebar edges, and hiding the macOS Dock while Nexus runs — with the snapshot rules that put it back exactly. |
| [`dock-parity.md`](dock-parity.md) | The gaps found by using it: Trash icon states without Full Disk Access, live drag reordering, an application's windows in its context menu. |
| [`window-previews.md`](window-previews.md) | Hovering an application to see its windows — the half of Milestone 4 that never shipped. |
| [`start-menu.md`](start-menu.md) | A browsable grid of everything installed, for when you cannot name what you want. |
| [`reserved-space.md`](reserved-space.md) | Keeping other applications' windows off the bar, when macOS offers no way to reserve the space. |
| [`bar-zones.md`](bar-zones.md) | What the bar always shows: a fixed head and tail, a scrolling middle, and a budget for each section. |
| [`now-playing.md`](now-playing.md) | What is playing, and the transport controls — without the private framework that would break on the next update. |
| [`media-player-row.md`](media-player-row.md) | The now-playing row as an actual player: inline controls, a draggable timeline, and no window previews. |
| [`search-scope.md`](search-scope.md) | Opening the palette at the bar, and telling it what kind of thing to look for. |
| [`multi-display.md`](multi-display.md) | Which monitors carry a bar: the menu-bar display, the one with the pointer, or every one of them. |
| [`app-groups.md`](app-groups.md) | Folders in the dock, and the configuration migration they bring with them. |

New feature? New file here, named after the feature. Keep it to what is specific — the focus,
permission and layout rules already live in `mvp.md`, and the reasons behind individual calls live
in [`../decisions.md`](../decisions.md).
