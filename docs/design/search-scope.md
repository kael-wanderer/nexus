# Search: where it opens, and what it searches

Milestone 19. Two changes to the palette: it can open at the bar rather than in the middle of the
screen, and it can be told what kind of thing to look for.

## Opening at the bar

Typing into the bar itself is the ask, and it is the one thing the bar cannot do: the sidebar panel
can never become key (`design/mvp.md` §2.1, and every AppKit control in it would render inactive if
it could). A text field nobody can type into is not a feature.

What is possible, and reads the same, is a **box** in the bar that opens the palette beside itself.
`search.barStyle` picks it:

| Setting | The bar shows | Clicking it |
|---|---|---|
| An icon (default) | One slot, a magnifying glass | Opens the palette in the middle of the screen |
| A search box | Three slots, a bordered box with a placeholder | Opens the palette 8 pt from the box |

The global shortcut is not part of that choice: `⌥Space` always centres the palette, because that is
what a hotkey means and what Spotlight does (D90). A narrow vertical bar keeps the icon whatever the
setting says — three rows of *height* buy a horizontal box nothing — and hover-expanding it makes
room, exactly as the wide player does.

Anchoring reuses `SidebarLayout.flyoutFrame`, the same placement the window flyout and the group
popover use, so a palette that grows as results arrive stays attached to the box: it grows *upwards*
off a bottom bar, and it clamps on screen, which is why the palette beside the last slot of a
2,513-point bar sits at the screen's edge rather than half off it.

## Scope

One filter, applied before ranking:

| Scope | What it searches |
|---|---|
| Everything | Applications, windows, files, folders, actions — today's behaviour |
| Applications | Application bundles only |
| Files & folders | Both |
| Files | Files, no folders |
| Folders | Folders only |
| Settings & Actions | The built-in actions, and every pane of System Settings |

- **Chosen with the keyboard**: `⌃1`…`⌃6` while the palette is open, and `⇥` / `⇧⇥` cycle. Not
  `⌘1`…`⌘6` — those already run the numbered result, and each row draws that badge (D87). The
  current scope is a chip in the field, and Escape clears the scope before it closes the palette —
  the same two-stage Escape a browser's find bar uses.
- **Also a menu.** The chip is the control that changes the scope, carrying the same `⌃N`
  shortcuts, so nothing here needs the keyboard.
- **Not remembered.** The palette opens on Everything every time: a scope chosen for one search is
  rarely the right default for the next, and a stored one is a filter the user cannot see the
  reason for three days later.
- **Files versus folders** is a Spotlight predicate, not a post-filter:
  `kMDItemContentTypeTree == "public.folder"` picks folders out and its negation picks files. The
  file provider already runs a metadata query, so this is one clause, not a new search.

Windows are reachable only from Everything. A window is not a category anybody goes hunting in — it
is the application they already named — and a seventh scope for it would cost a shortcut to save
nobody a keystroke.

Scope also answers a question the provider toggles could not: those switch a provider off for
everybody, forever. A scope is for this search.

**Settings & Actions** reaches the action provider, and that provider now has both halves of
"things you do rather than open": the built-in actions, and every pane of System Settings.

The panes are not a Spotlight query. System Settings has been a set of ExtensionKit extensions
since macOS 13, and the panes on the sealed system volume are not indexed — asking Spotlight for
`public.prefpane` returns nothing at all on this machine. `/System/Library/ExtensionKit/Extensions`
is, so each `.appex` there is read once for the two things worth having: the legacy identifier that
`x-apple.systempreferences:` takes, and a name. Extensions whose own `Info.plist` says they do not
accept that URL scheme are skipped, because a result that does nothing is worse than no result.

Naming them takes one rule. The extension's display name is usually right — Displays, Keyboard,
Screen Time — and sometimes it is the developer's bundle name, `AccessibilitySettingsExtension` or
`MouseExtension`. Where the extension names a legacy `.prefPane`, that pane's `CFBundleName` wins,
because it is the string System Preferences used to draw; otherwise the bundle name is tidied —
trailing `Extension` dropped, `DateAndTime` split back into words.

The scope is called **Settings & Actions** rather than Settings for the same reason: it holds both,
and a filter that says one thing and shows another is worse than a longer name.

## Rules it inherits

- Ranking, frecency and the 50 ms budget are unchanged (`design/mvp.md` §5): a scope narrows the
  candidate set before ranking, and narrowing cannot make it slower.
- The palette still dismisses on Escape, on an outside click, and on losing the keyboard.

## Tests

- Each scope excludes what it should and keeps what it should.
- Folders-only and files-only are complements over the same query.
- `⌃3` selects a scope and re-runs the query without a keystroke of input.
- Escape with a scope set clears the scope; Escape again closes the palette.
- The box opens the palette beside itself on all four edges, clamped on screen; the global shortcut
  centres it whatever the setting says.
- The box costs the tail three slots and the icon one, and a narrow vertical bar keeps the icon.
- A pane's name comes from its legacy `.prefPane` where there is one, and from a tidied bundle name
  where there is not; an extension that does not take the URL scheme is not a result.
- The real `/System/Library/ExtensionKit/Extensions` yields panes, including Displays and Keyboard —
  a test against the machine it runs on, so a macOS change that moves the directory is a failure
  rather than an empty scope.
