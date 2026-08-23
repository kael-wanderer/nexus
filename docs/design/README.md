# Design

One file per feature.

| | |
|---|---|
| [`mvp.md`](mvp.md) | The cross-cutting design, and the MVP surface: panels and focus (a sidebar that can never become key, a palette that deliberately activates), permissions as capabilities, the layout vocabulary, search, displays, accessibility. Everything else inherits from here. |
| [`dock-replacement.md`](dock-replacement.md) | Four sidebar edges, and hiding the macOS Dock while Nexus runs — with the snapshot rules that put it back exactly. |
| [`dock-parity.md`](dock-parity.md) | The gaps found by using it: Trash icon states without Full Disk Access, live drag reordering, an application's windows in its context menu. |

New feature? New file here, named after the feature. Keep it to what is specific — the focus,
permission and layout rules already live in `mvp.md`, and the reasons behind individual calls live
in [`../decisions.md`](../decisions.md).
