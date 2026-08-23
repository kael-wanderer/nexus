# Zones: what the bar always shows

Milestone 14. With thirty applications running, Trash and Search scroll off the end of the bar and
have to be hunted for. They are not rows like the others and should never have scrolled.

## The bug, precisely

`SidebarView` puts the whole bar in one `ScrollView`, and `SidebarLayout.frame` clamps the panel to
the screen. Past roughly twenty-four rows the content is longer than the panel, so *everything*
scrolls — the launcher at one end and Trash and Search at the other along with the applications.

## Zones

The bar becomes three parts, and only the middle one scrolls:

```
┌──────────┐   fixed head      start menu (when on)
│ ▦ Apps   │   ───────────
├──────────┤
│ ▣ Safari │   scrolling       pinned applications, groups and folders, up to `pinnedLimit`
│ ▣ Xcode  │   middle          ───────────
│ ▣ Slack  │                   running applications, up to `runningLimit`
│ ▣ Music  │
├──────────┤   ───────────
│ ♫ Track  │   fixed tail      now playing (M15), minimized windows (M22),
│ ▫ Draft  │                   Trash, Search
│ 🗑 Trash  │
│ ⌕ Search │
└──────────┘
```

The head and the tail keep their rows whatever else happens. The middle gets what is left of the
screen and scrolls inside it.

The tail is not one part but four — now playing, minimized windows, Trash, Search — and each is drawn as its own
section, so the separator the bar already puts between sections falls between them too. Six parts,
six kinds of thing, and the zone maths counts one separator per fixed section rather than one for
the tail as a whole (D77).

## Thickness: the icons decide, not the number

`appearance.width` is the **vertical** bar's measurement. A horizontal bar's thickness is computed
from the icon size instead — the icon, its padding, and the running dot drawn under it — and the
configured width only wins when it is larger than that. Using `width` on its side is what put a
64 pt icon in a 64 pt bar and cut its feet off, dots first (D102).

## Budgets: the screen decides, not a number

The bar grows until it runs out of edge, and only then scrolls. What "runs out" means is measured,
because it differs per edge and per display:

- a **left or right** bar measures the screen's usable **height**
- a **top or bottom** bar measures its usable **width**

On a 1920 × 1080 display those are wildly different numbers of icons, so the capacity is computed
rather than configured:

```
slots = wholeRows(usable − head − tail − separators − padding)
```

`slots` is every application row this edge of this screen can hold. The head (the launcher) and the
tail (now playing, Trash, Search) are subtracted first and are never squeezed — a row that is
turned off costs nothing, which is why switching the now-playing row off gives its slot back to the
applications.

The slots are then handed out:

1. Running keeps a floor of **2 rows** whenever anything is running — the ask behind "always show
   1-2 unpinned apps". A dock full of pins must not hide the fact that other applications are open.
2. Pinned takes what is left.
3. Running takes whatever pinned did not need.
4. Past that, each section scrolls **inside its own extent**. Overflow is reachable; the tail never
   moves.

`appearance.pinnedLimit` and `appearance.runningLimit` are **ceilings on top of that**, not the
number of rows: **0** means "as many as fit" and is the default. Set one to 8 and you will never see
a ninth pinned row even on a tall screen; leave it at 0 and the bar uses the screen it has.

## Why a ceiling exists at all

Because a person with sixty pins on a tall display may still want the running section visible
without scrolling to it. The screen is the rule; the ceiling is for when you want less than the
screen offers. It is never a way to get *more* than fits.

## Rules it inherits

- `SidebarPosition.isVertical` picks the axis, as everywhere (`design/mvp.md`). Above or below a
  horizontal bar the zones run left-to-right: head at the leading end, tail at the trailing one.
- The panel is still one non-activating panel; zones are layout, not new windows.
- Reserved space (M12) re-sweeps whenever the bar's frame changes, which a zone change is.

## What shipped

The zones as specified. The budgets shipped twice: first as fixed limits of 10 and 5, which was
wrong — a bar with half the screen empty still scrolled — and then as the measured `slots` above,
with the limits demoted to optional ceilings (D74). Configuration version 3 resets the two values
the first version wrote, because they were defaults nobody chose.

Two notes:

- The limits live in `appearance`, not `behavior`, next to icon size and spacing — they are about
  how much bar there is, not about what it does. Settings → Appearance, two steppers, where 0 reads
  as "Fit the screen".
- `sectionRowCounts` now reports *visible* rows rather than every row a section holds, because it
  is what the flyout anchor measures against (`SidebarLayout.rowCentre`). A capped section's rows
  are the ones on screen, so an anchor can never point past the panel.

Verified live, 24 applications running: before, 962 pt of everything-scrolls with Trash and Search
off the end. After, the bar fills the edge — 1255 pt, which is exactly the fixed 207 plus five
pinned rows and fourteen of nineteen running ones — and the remainder scrolls inside its section
while the tail stays put.

## Tests

- With 30 running applications the tail rows are inside the panel's frame, not past it.
- A taller edge shows more rows than a short one, and neither shows more than it holds.
- The same display holds a different number of rows on a side edge than on a main one.
- Running keeps its two-row floor when the pinned section wants everything.
- A ceiling, when one is set, binds before the screen does.
- Both limits count a group as one row.
- `rows(fitting:)` survives an extent that is not a real screen.
