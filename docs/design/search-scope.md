# Search: where it opens, and what it searches

Milestone 19. Two changes to the palette: it can open at the bar rather than in the middle of the
screen, and it can be told what kind of thing to look for.

## Opening at the bar

Typing into the bar itself is the ask, and it is the one thing the bar cannot do: the sidebar panel
can never become key (`design/mvp.md` §2.1, and every AppKit control in it would render inactive if
it could). A text field nobody can type into is not a feature.

What is possible, and reads the same, is opening the palette **anchored to the Search row** instead
of at 62% of the screen height — beside a vertical bar, above or below a horizontal one, exactly
where the window flyout appears. The palette is already its own activating panel; only its position
changes.

`search.opensAtBar`, default **on** once this ships. The centred position stays available, because
on a large display the middle of the screen is where the eye already is.

## Scope

One filter, applied before ranking:

| Scope | What it searches |
|---|---|
| Everything | Applications, windows, files, folders, actions — today's behaviour |
| Applications | Application bundles only |
| Files & folders | Both |
| Files | Files, no folders |
| Folders | Folders only |
| Settings | System Settings panes and Nexus's own actions |

- **Chosen with the keyboard**: `⌘1`…`⌘6` while the palette is open, and `⇥` cycles. The current
  scope is a chip in the field, and Escape clears the scope before it closes the palette — the same
  two-stage Escape a browser's find bar uses.
- **Remembered per session, not stored.** A scope chosen for one search is the wrong default for the
  next one; the palette opens on Everything unless `search.defaultScope` says otherwise.
- **Files versus folders** is a Spotlight predicate, not a post-filter:
  `kMDItemContentTypeTree == "public.folder"` picks folders out and its negation picks files. The
  file provider already runs a metadata query, so this is one clause, not a new search.

Scope also answers a question the provider toggles could not: those switch a provider off for
everybody, forever. A scope is for this search.

## Rules it inherits

- Ranking, frecency and the 50 ms budget are unchanged (`design/mvp.md` §5): a scope narrows the
  candidate set before ranking, and narrowing cannot make it slower.
- The palette still dismisses on Escape, on an outside click, and on losing the keyboard.

## Tests

- Each scope excludes what it should and keeps what it should.
- Folders-only and files-only are complements over the same query.
- `⌘3` selects a scope and re-runs the query without a keystroke of input.
- Escape with a scope set clears the scope; Escape again closes the palette.
- Opening at the bar puts the palette beside the Search row on all four edges, clamped on screen.
