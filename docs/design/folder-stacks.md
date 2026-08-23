# Folder stacks

**Milestone 21.** A folder in the bar: drop one in, click it, see what is inside.

The macOS Dock's right-hand side is folders — Downloads above all — and Nexus has no answer to it.
Everything a stack needs already exists here: the dock stores entries rather than bundle
identifiers (M13), the group popover already draws a grid beside the bar, and the bar already
accepts a drop from Finder. What is missing is a third kind of entry and something to list a
directory.

## The entry

`DockEntry` gains a case:

```swift
case folder(String)     // a path, not a bookmark: Nexus is not sandboxed
```

Stored as `{"folder": "/Users/x/Downloads"}`, beside `{"application": …}` and `{"group": {…}}`, so
`defaults read` stays legible. Its `id` is `folder:` + the path — distinct from a bundle
identifier and from a group's `group:` prefix, stable across a reorder, and the thing every
existing drag, drop and Move Up/Down already works in terms of.

A path rather than a security-scoped bookmark because Nexus has no App Sandbox: a bookmark would
buy nothing but a resolve step. A folder moved or deleted since it was pinned keeps its row and says
so when opened — *This folder is no longer there* — rather than vanishing from the dock on its own.
A row the user put there is theirs to remove.

`NexusConfiguration.version` goes **4 → 5** with an empty migration, which looks like ceremony and
is not. The change is additive, so nothing stored needs rewriting — but a build that only knows v4
*throws* on `{"folder": …}` while decoding the entry list, and a throw means the file is quarantined
and the dock resets. A version it does not recognise is the one case the store already handles
gently: it runs on defaults without overwriting what it cannot read. The bump buys a safe
downgrade.

## Reading the folder

One service, `FolderStackService`, with one job: given a URL, return what is in it.

- Hidden files are skipped (`.DS_Store` is not a stack item), as are package *contents* — an `.app`
  is one item, not a directory to walk into.
- Sorted folders first, then files, each alphabetical by localized name. Sorting by date is what the
  Dock offers as an option; it is one comparator, and it can wait until somebody asks.
- Capped at 60 items. A stack is a glance, not a file manager, and a `LazyVGrid` of 4,000 entries in
  a panel beside the bar is a way to make the bar feel slow.
- Read when the stack opens, not watched. A folder that changes while its popover is open is rare
  enough that a re-read on the next open is the honest trade against an `FSEvents` stream per
  pinned folder.

**Permission is the interesting case.** Desktop, Documents and Downloads are TCC-protected, so the
first read of one prompts, and a refusal comes back as an error rather than an empty folder. Those
are different things and the popover says which: a folder Nexus may not read shows one line —
*Nexus needs permission to read this folder* — and a button that opens it in Finder, which is both
useful and the thing that makes macOS ask again. An empty folder says *Empty*.

## The row and the popover

The row draws the folder's own icon (`NSWorkspace` gives the custom one for free, which is what
makes a Downloads stack look like Downloads) at the same size as an application row, with the
folder's name when the bar is expanded. No running dot, no window count: a folder is not running.

Clicking opens a popover beside the bar, positioned exactly like the group popover and under the
same rules — a non-activating panel, so no text field, dismissed by a click outside or by the
pointer leaving. Its grid is the group popover's grid with file tiles instead of application tiles:
icon, name over two lines, click to open.

- Clicking a file opens it in its default application.
- Clicking a subfolder opens it in Finder rather than drilling in. Drill-down means a navigation
  stack, a back button and a title bar in a panel that cannot take focus; opening Finder is what
  the user wanted from a folder-of-folders anyway.
- The header names the stack and says how many items, `12 items`, so a capped listing is not a lie.

## Interaction

- **Add**: drag a folder from Finder onto the bar. The same drop handler that pins an application
  takes a directory as a folder entry; an `.app` is still an application, because a bundle is a
  directory and the specific case wins.

  The drop is AppKit's, on the bar's hosting view, not SwiftUI's `.dropDestination`. The row
  overlays that own clicks and reordering (D39) sit on top of the SwiftUI view, and a drop over one
  of them — which is most of the bar — never reached it. They register only Nexus's own row type, so
  a file drag falls through to the view underneath, which is where it is now handled.
- **Remove**: the row's context menu — Remove from Bar — beside the Move Up / Move Down / Move to
  End the other rows have.
- **Open in Finder**: the same menu, and the popover's header.
- **No grouping**: dropping a folder onto an application does not make a group. A group is a group
  of applications (M13), and a folder in one would have to answer what its dot means and what
  clicking a member does. Dragging a folder reorders it, nothing else.

## Settings

None. A folder in the bar is there because the user put it there, and a switch to turn folders off
is a switch to hide rows the user created — which is what removing them is for.

## Tests

- A folder entry round-trips through JSON and reads back as the same path; an unknown entry kind
  still throws rather than being silently dropped.
- `repaired` keeps folders, drops empty paths, and de-duplicates the same folder pinned twice.
- Listing a temporary directory returns its contents, folders first, hidden files excluded, capped.
- A directory that cannot be read is reported as refused, not as empty.
- The drop handler pins a directory as a folder, an `.app` as an application, and refuses a plain
  file.
- Opening a stack whose folder has been deleted reports it as missing, not as empty.

## Acceptance criteria

- Dragging `~/Downloads` from Finder onto the bar puts a Downloads row on it, with its own icon,
  that survives a restart.
- Clicking the row opens a grid of what is in the folder, beside the bar, on the display the bar
  is on; a click outside closes it.
- Clicking a file in the grid opens it; clicking a subfolder opens that folder in Finder.
- A TCC-protected folder that has not been granted shows the permission line, not an empty grid.
- Remove from Bar takes the row off, and the rest of the dock keeps its order.
