# Keyboard control of the bar

**Milestone 23.** `⌃F3` puts the keyboard on the bar; arrows walk it, Return opens what is focused,
Escape gives the keyboard back.

The palette has been keyboard-first since Milestone 5 and VoiceOver can press every row since D88,
but a sighted keyboard user had no way into the bar at all: it is a pointer target and nothing else.
macOS solves this for its own Dock with `⌃F3`, and that is the shortcut Nexus takes — the real Dock
is hidden while Nexus is the dock, and the muscle memory is already there.

## The one exception to "never key"

The sidebar panel can never become key (D3): that guarantee is what keeps clicking the bar from
disturbing the insertion point in whatever you were typing in. Keyboard control needs the opposite,
so it takes the palette's bargain instead — the panel becomes key **because the user asked, with a
shortcut**, and stops being key the moment they leave.

`NonActivatingPanel.acceptsKeyboardFocus` is that flag, and `canBecomeKey` returns it. Nothing sets
it except entering keyboard mode; four things clear it:

- Escape, or the shortcut pressed again,
- opening whatever is focused — the row's own action usually puts another application in front, and
  holding the keyboard after that would take it back from the thing just asked for,
- the panel losing key status to anything else, including a click into another window,
- ten seconds of no keys at all.

The last one is insurance rather than a feature. A bar that kept the keyboard because something went
wrong is a machine that will not type, and that is not a bug worth risking for the sake of purity.

When the mode ends the keyboard goes back where it came from: the application that was frontmost
when the shortcut fired is activated again, exactly as closing the Settings window does (D93).

## Walking the bar

The order is the order the bar draws: the launcher, the dock (applications, groups, folders), the
running applications, the minimized windows (M22), Trash, Search.

- **Both axes work.** `←`/`↑` is the previous row and `→`/`↓` the next, whichever edge the bar is
  on, because a person pressing `→` on a bottom bar means what `↓` means on a left one.
- **Home** and **End** jump to the ends.
- **Return**, **Enter** and **Space** do what clicking the row does: launch or activate an
  application, open a group, show a folder's contents, restore a minimized window, open the Trash,
  open the palette.
- **Escape** leaves.
- Everything else travels on untouched, so a key the bar does not use is not a key the bar eats.

The now-playing row is deliberately not in the walk. It is three targets in one row, and the
transport keys on the keyboard already reach the player from anywhere — including from inside
another application, which is better than what a focus ring could offer.

## Seeing where you are

The focused row draws a two-point tinted ring — a shape the hover highlight never draws, so the two
are not told apart by colour alone (`design/mvp.md` §9). Every focusable row carries it: application,
group, folder, minimized window, Trash, Search icon and Search box alike.

## Settings

Settings → Behavior: **Keyboard access to the bar**, on by default, and a recorder for the shortcut
when it is on. Switching it off unregisters the hotkey and leaves the bar exactly as it was — a
pointer target.

## Rules it inherits

- The hotkey is Carbon's, like the palette's, and needs no permission (§111.1). `HotKeyService` now
  registers one shortcut per *slot* rather than one in total.
- A shortcut some other application already owns simply fails to register, and that is logged rather
  than reported: the bar still works without it.
- Auto-hide reveals the bar first — there is no point putting the keyboard on something invisible.

## Tests

- The focusable rows are the rows the bar draws, in drawing order, including minimized windows
  between the applications and the Trash.
- Entering asks the panel for the keyboard; leaving gives it back; leaving twice asks nothing twice.
- Arrows stop at each end rather than wrapping; Home and End jump.
- Return runs the focused row and ends the mode; a focused minimized window is restored.
- Both arrow axes map to the same two commands, and an ordinary key maps to none.
- The shortcut is on by default and can be switched off.

## Acceptance criteria

- `⌃F3` rings the first row; arrows move the ring; Return opens what it is on.
- Escape returns the keyboard to the application that had it.
- Typing into another application after leaving works with no click in between.
- With the setting off, `⌃F3` does nothing and the bar is unchanged.
