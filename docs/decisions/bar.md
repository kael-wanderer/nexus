# Decisions — The bar

Panels and focus, zones and rows, dragging, and what a dock slot can be: an application, a group, a folder.

Part of the decision log; the index, and the rule these follow, are in
[`../decisions.md`](../decisions.md). Numbers are global and never reused, so the gaps
here are entries that live in another file, and the date each was made is in `git log`.

## D3. Sidebar panel can never become key; the search palette activates the app deliberately.
The two panels have opposite focus requirements, so they get opposite designs rather than one
shared abstraction. Details in `docs/design/mvp.md` §2.

## D4. Auto-hide reveal uses a 2 pt transparent edge-trigger panel with a tracking area.
Event-driven and permission-free. Rejected `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`:
wakes the process on every mouse move for a feature that fires a few times a minute.

## D17. `Force Quit` is always present in the sidebar context menu, not revealed "after a
timeout".
A context menu cannot be re-shown after a quit request times out, and the Dock
behaves the same way. Nexus never blocks on `terminate()`, so a refusing application (unsaved
document) cannot hang the sidebar — which is the acceptance criterion the timeout wording was
protecting.

## D19. The running-but-unpinned section shipped with the sidebar at Milestone 2.
It needs no permission and no new code beyond a filter, and an empty sidebar on first launch is a
poor first impression. Milestone 3 added only the event plumbing that keeps it live.

## D39. Clicks inside a panel that can never become key are handled in AppKit, not by SwiftUI's
`.onTapGesture`.
Root cause of "clicking the sidebar / palette does nothing". A click into a
non-key window is discarded unless the **view that is actually hit** returns
`acceptsFirstMouse == true`; overriding it on the `NSHostingView`, as `design/mvp.md` §2.1
assumed, is not enough, because the hit view is one of SwiftUI's internal subviews. And because
the sidebar can *never* become key, every click is a first-mouse click — so the taps did not
merely fail once, they never worked at all. `PanelRowInteraction` (the former
`ContextMenuCatcher`) now claims left- and right-press events, returns `acceptsFirstMouse = true`,
and distinguishes a click from a drag with a 5 pt slop. It is applied to every clickable row in
a non-key surface: sidebar items, the search row, flyout window rows, and the grant screen's own
buttons — which is why "Open System Settings" was also dead. Rejected: making the sidebar
key-capable, which would break the product's central guarantee.

## D44. Pinned reorder is available from the context menu.
`PanelRowInteraction` claims mouse-down, which is also where a SwiftUI `.draggable` would begin,
so drag-reorder cannot be relied on in the sidebar. Working clicks matter more than working
drags, and `design/mvp.md` §2.1 already listed a manual reorder as the sanctioned fallback.
Move Up / Move Down / Move to End are now in the context menu, correctly disabled at the ends.
`.draggable`/`.dropDestination` are left in place and cost nothing; dropping an application from
Finder onto the sidebar to pin it is unaffected, because that drop target is the container, not
the row.

---

## D46. The sidebar scrolls.
Clearing the contaminated configuration immediately exposed a real
defect behind it: 25 running applications need 1469 pt on a screen with 1325 pt of usable
height. `SidebarLayout.frame` clamped the *panel* to the screen but nothing clamped the
*content*, so the last rows were simply cut off. The row stack now lives in a `ScrollView`.
Verified: the same 25 applications now produce a 1310 pt panel that fits, with the overflow
reachable by scrolling. `PanelRowInteraction` (D39) already ignores `.scrollWheel` events, so
scrolling passes through to SwiftUI untouched.

## D53. Hover-expand is vertical-only.
A horizontal bar growing taller on hover would shove every window on the screen. The toggle stays
in Settings and says so while the position is top or bottom, rather than silently doing nothing.

## D55. The Trash row has no full/empty state.
Reading `~/.Trash` needs Full Disk Access — `kTCCServiceSystemPolicyAllFiles` for
`com.congbui.nexus` is an explicit deny on this machine — and a failed read is indistinguishable
from an empty Trash. The first build drew "empty" over a Trash holding 42 items. One icon that
never claims to know beats an icon that is silently wrong whenever the grant is missing, and an
icon is not worth asking for access to every file on the disk.

## D56. Drag-to-reorder is an AppKit dragging session inside `PanelRowInteraction`, not SwiftUI.
Supersedes D44's "reorder by context menu only". The sidebar panel can never become key, so the
row interaction has to claim every mouse-down for a plain click to work at all, which means
SwiftUI never sees a drag start — `.draggable` was dead code. `mouseDragged` past the same 5 pt
slop that already separates a click from a press starts an `NSDraggingSession` carrying a private
pasteboard type (`com.congbui.nexus.sidebar-row`), so a text drag from another application can
never reorder anything, and the source mask is `.move` only within Nexus. Dropping a running
application onto a pinned row pins it in that slot. The context-menu items stay: they are the
keyboard-reachable path.

## D57. Empty Trash goes through Finder and asks first.
`tell application "Finder" to empty trash` keeps the "put back" bookkeeping and the locked-item
rules that a hand-rolled `FileManager` delete would skip. It needs Automation access for Finder,
requested on first use; a refusal leaves the Trash untouched and is logged. The confirmation
alert is the one modal in the sidebar — the action cannot be undone.

## D58. Supersedes D55: the Trash row shows full vs empty again, counted with `stat`.
`readdir` on `~/.Trash` needs Full Disk Access, which Nexus is denied — but `stat` is not gated,
and on APFS a directory's `st_nlink` is `2 + entry count`. Measured from inside Nexus:
`contentsOfDirectory` → `nil`, `stat(~/.Trash)` → `nlink=44` for 42 items, `stat` of a file that
does not exist → fails, so it is a real answer rather than a blanket yes. Finder's own
`.DS_Store` and `.localized` are subtracted by name: Finder recreates `.DS_Store` the moment the
Trash window opens, and counting it would leave the full icon showing over an empty Trash. The
icons are the ones macOS itself uses, from `CoreTypes.bundle`, which is not protected either.

## D59. A drag shows a preview order; the configuration is written once, on drop.
The dragged row fades to 35 % and `SidebarViewModel` holds a transient `previewOrder` that the
rows are sorted by, so the others slide out of the way exactly as they do in the Dock. Rows are
keyed by bundle identifier, so SwiftUI animates the moves on its own. A drag that is cancelled or
dropped outside restores the stored order — writing on every `draggingUpdated` would leave a
reordered dock behind after an abandoned drag.

## D59 (extended). Running applications get the drag preview too.
The first cut previewed only pinned rows, so dragging a running application into the dock did
nothing until the drop — the exact failure the preview was added to fix. The preview order is now
a list of identifiers that may include an application that is not pinned yet; it leaves the
running section as the drag reaches the pinned one, and the drop is what pins it. A cancelled drag
puts it back.

## D63. The running section has a user order too, and a drag can cross the separator.
Reordering only worked when the drop landed on a *pinned* row, so dragging one running
application onto another — the common case, "put Claude left of ChatGPT" — did nothing, which is
what "drag still does not work" meant. The running section now has its own stored order
(`runningApplicationOrder`), holding only the applications the user has actually moved; everything
else keeps its alphabetical place behind them, so the section does not shuffle itself when an
application launches. A drag lands in whichever section the row under the pointer belongs to,
which makes dragging across the separator pin or unpin — the same gesture the Dock uses.

## D71. Grouping is asked for by resting on a row, not by dropping on it.
The dock previews a reorder as the pointer moves (D59), which means the rows have already shifted
by the time a drag is over a row: "drop on Safari" and "drop between Safari and Terminal" are one
gesture, and only timing separates them. So a drag that rests on a row for 600 ms changes meaning
— the preview reverts, the dragged row leaves the bar, the target grows a ring, and letting go
merges the two. Dragging straight past a row reorders exactly as before. This is what iOS does,
and the dwell is what makes it discoverable without a modifier key nobody would find.

The name comes from `LSApplicationCategoryType`, which applications already declare and
LaunchServices already hands over with the icon: the category most members share, mapped to a word,
falling back to "Group". Renaming lives in the row's context menu behind an alert rather than in
the popover's header, because the popover can never become key and a text field nobody can type
into is worse than a menu item.

## D72. The dock repairs itself rather than trusting what it stored.
`[DockEntry].repaired(capacity:)` runs on decode and after every edit: an over-full group keeps its
first members, an application listed twice keeps its first slot, a group of one becomes that
application, an empty group disappears. Capacity is a setting, so yesterday's nine-member group is
today's over-full one when it changes — enforcing it in one place means a hand-edited `defaults`
payload, a capacity change and a drag all end up in the same state. The stored v1 key
`pinnedApplications` is still written beside the entries so a downgrade finds its dock; nothing
reads it.

## D73. The bar has three zones, and only the middle one scrolls.
Everything used to live in one `ScrollView` clamped to the screen, so past about two dozen rows
Trash and Search scrolled off the end and had to be hunted for. They are not rows like the others:
the launcher is a fixed head, Trash and Search (and later now-playing) are a fixed tail, and the
applications are a scrolling middle between them.

The middle gets a row budget per section — `appearance.pinnedLimit` (10) and
`appearance.runningLimit` (5) — resolved after the head and tail have taken their space, never
before. When the screen cannot hold both budgets, running keeps a floor of two rows and pinned
takes what is left: a dock full of pins must not hide the fact that other applications are open.
Overflow scrolls inside its own section, so nothing becomes unreachable, and both limits count a
group as one row — which is what makes groups worth having.

Limits rather than unbounded scrolling because scrolling to reach Search was the complaint. A bar
that grows without bound is a list; the overflow already has better answers than length — groups
for the applications you keep, the palette and the start menu for the ones you do not.

## D74. The bar's length is measured, not configured.
Milestone 14 first shipped fixed budgets — ten pinned rows, five running — and they were wrong
within the hour: a bar with half the screen empty still scrolled to reach an application. The
number of rows an edge holds is not a preference, it is a measurement, and it differs per edge and
per display. A left or right bar has the screen's height to spend; a top or bottom bar has its
width. On 1920 × 1080 that is a different dock.

So capacity is computed — `slots = wholeRows(usable − head − tail − separators − padding)` — and the
two settings become ceilings on top of it, with **0** meaning "as many as fit" as the default. A row
that is switched off gives its slot back, which is what makes turning off the now-playing row worth
something. Scrolling begins where the screen ends, and not before.

Configuration version 3 exists only to reset the two values version 2 wrote: they were defaults
nobody chose, and keeping them would preserve the bug. A ceiling set deliberately after this point
is stored against the new meaning and survives.

One implementation note worth keeping: `rows(fitting:)` is called on every layout pass now, so it
has to survive being asked about an extent that is not a real screen. It was first written to trust
its input and trapped converting an infinite extent to `Int` — the model passes a large finite
extent before the first reframe, and the function caps its own answer.

## D77. The bar is six parts, and it says so.
Launcher, pinned, running, now playing, Trash, Search. They were already six *kinds* of thing but
only three of them were separated, so the tail read as one undifferentiated clump — and with the
now-playing row in it, as a duplicate of the application it was playing. Each part is its own
section now, which means each gets the separator the layout already draws between sections, and the
zone maths counts one separator per fixed section rather than one for the whole tail.

## D78. "Nexus is my Dock" is one choice, not a toggle in a list.
Running Nexus at the bottom of the screen with the macOS Dock still there gives you two docks, which
is nobody's intention. The Dock pane now opens with a two-way choice — *My Dock*, which hides the
system Dock while Nexus runs (D51/D52 do the work), or *A sidebar*, which leaves it alone. The
setting underneath is the same `dock.replacementEnabled`; what changed is that it now reads as the
decision it is, and says which of the two you are looking at.

## D79. Icons default to the size of a Dock tile.
40 points was the default because it looked right in a narrow sidebar. Next to the macOS Dock it
looks like a downgrade: a dock replacement with smaller icons than the dock it replaces. The default
is 64 — a Dock tile at its own default — and configuration version 4 rewrites a stored 40, since
nobody chose it while it was the default. Any other size was set by hand and is kept.

## D81. A click outside closes a popover, without waiting for the pointer to leave.
The window flyout, the group popover and the media player all hid on a 400 ms grace period after the
pointer left, and on nothing else. A non-activating panel never loses key status — it never had any —
so there was no resign-key to hook, and clicking somewhere else left the popover sitting there. The
same global mouse monitor the palette needed (a click in another application never reaches a panel
that is not theirs) closes whichever popover is open, with the bar itself excluded: clicking the
media row is what opened it.

## D82. The wide media player spans four rows rather than becoming a section of its own.
Two tiles with the scrubber hidden in a popover lasted an hour of real use. Four tiles is right on a
horizontal bar — but a section with its own pitch would have meant teaching `sectionExtent`, the
`slots` arithmetic and `rowCentre` to work in points instead of rows, which is the maths every other
part of the bar depends on.

So the wide player is one view sized to four rows' worth of extent. Everything stays row-based, the
change is a view and a row count, and the space it costs is visible in the same arithmetic as
everything else: four slots that the applications no longer get (D74). Which is also why it is a
setting — and why a narrow vertical bar ignores it, since four rows of height cannot hold a scrubber
worth dragging.

## D93. Closing a window must not hide the application.
Closing Settings called `NSApp.hide(nil)`, so that an agent app with no windows left did not sit
there "active". It hides *every* window the application owns, and a panel is a window: both bars
vanished, the menu-bar item was the only sign Nexus was running, and the only way to get them back
was to open Settings again — which is exactly how it was reported.

Two changes, because one was not enough. The panels now set `canHide = false`, which is the property
that exists for precisely this: a bar is not a document window and has no business disappearing
because the application was hidden. And the close handler hands focus back the way the palette
already does — by activating the application that had it before, falling back to `NSApp.deactivate()`
— rather than hiding this one.

The second half matters beyond the bars: an application flagged hidden publishes no windows to the
accessibility tree, so `canHide = false` alone would have kept the bars on screen and left VoiceOver
unable to find them (D88).

## D94. A menu item that toggles says which way it toggles.
"Toggle Sidebar" said nothing about the state it was toggling from, and it was read as a *mode*
switch — a way to move the bar from the bottom edge to the side — rather than as show/hide. Nothing
else on the menu says where the bar is either, so a bar hidden by mistake looks like Nexus running
with nothing to show for it.

The item now reads `Hide Nexus Bar` or `Show Nexus Bar`, built from the live state the same way the
Dock row above it is (`isDockHidden`). The name changed with it: "Sidebar" is the code's word for the
panel and dates from when it only sat on a side; on the menu it is the Nexus Bar, wherever the user
has put it. A checkmark was the other option, and says less: a tick beside "Toggle Sidebar" still
does not say what unticking does.

## D96. A folder in the dock is a path, and what it cannot read it says out loud.
Three choices worth writing down from Milestone 21.

*A path, not a bookmark.* A security-scoped bookmark is the sandboxed answer to "remember this
folder", and Nexus has no App Sandbox: the bookmark would be resolved on every read and buy nothing.
The cost is that a folder moved after it was pinned stops resolving — so the row stays and says
*This folder is no longer there* when opened, rather than deleting itself out of the dock. A row the
user put there is theirs to remove.

*Refused is not empty.* Desktop, Documents and Downloads are TCC-protected, and
`contentsOfDirectory` answers a refusal with an error, not with zero entries. Flattening the two
into "nothing here" would be a dead end for the user; the popover shows one line of explanation and
an Open in Finder button, which is both what they wanted and what makes macOS ask again.

*Version 5 for an additive change.* The store's own rule is that additive changes need no
migration, and this one is additive — but the failure it prevents is not in this build. A v4 build
reading `{"folder": …}` **throws** while decoding the dock, and a throw quarantines the file and
resets the dock. A version it does not recognise is the one case the store handles gently: run on
defaults, overwrite nothing. So the number moves, with an empty migration, and a downgrade costs a
session rather than a dock.

## D99. The bar takes the keyboard only when asked, and gives it back four ways.

The sidebar panel can never become key (D3), which is the guarantee that keeps clicking the bar from
disturbing what you were typing. Keyboard control needs the opposite of that, so it takes the
palette's bargain rather than breaking the rule: the panel becomes key **because the user pressed a
shortcut**, and stops being key the moment they leave.

`acceptsKeyboardFocus` on the panel is the whole mechanism — `canBecomeKey` returns it, and nothing
sets it except entering the mode. Leaving it is deliberately over-determined: Escape or the shortcut
again, opening the focused row (its action usually puts another application in front, and keeping
the keyboard after that would take it back from the thing just asked for), the panel losing key
status to anything else, and ten seconds of no keys at all.

That last one is insurance, not a feature. A bar still holding the keyboard because something went
wrong is a machine that will not type, and no amount of purity is worth that.

`⌃F3` because macOS uses it to focus its own Dock, and the real Dock is hidden while Nexus is the
dock. A shortcut another application already owns fails to register, which is logged and otherwise
ignored: the bar is a pointer target either way. `HotKeyService` grew a slot per shortcut to make
room for it — Carbon identifies a hotkey by number, so the slot *is* that number.

## D101. `⌃F3` is not ours to take, and keys belong to the window.

Two things wrong with the first cut of keyboard control (D99), both found by pressing the keys on a
real machine rather than by reading the code.

**The shortcut.** `⌃F3` is what macOS uses to move focus to its own Dock, and the system consumes it
before a Carbon hotkey ever sees it — whether or not the Dock is hidden. `RegisterEventHotKey`
succeeds and the handler never fires, which is the worst shape a bug can have: the log says
"registered" and nothing happens. The default is now `⌃⌥Space`, beside the palette's `⌥Space`, and a
stored `⌃F3` is replaced on load rather than honoured, since nobody chose it — it was a default for
one build.

**The keys.** `keyDown` was overridden on the bar's `NSHostingView`, and it never ran: inside a
hosting view the first responder is one of SwiftUI's own subviews, so the event is handled (or
swallowed) below the override. The panel is the one object guaranteed to be in the chain, so
`NonActivatingPanel` handles the keys and hands each one to `PanelController`, which returns whether
it was used. Anything the bar does not use travels on untouched.

## D102. A horizontal bar's thickness is its icons' business, and an alert opens where the click was.

Two things the bottom edge got wrong, both reported as "it looks tight".

**Thickness.** `appearance.width` is the *vertical* bar's measurement, and laying it on its side kept
using it: a 64 pt bar holding a 64 pt icon has nothing left for the icon's own padding, let alone the
running dot underneath it. So the dots — the thing that says an application is open — were the first
pixels off the screen. A horizontal bar now computes its thickness from the icon size and only
honours `width` when the number is larger than the icons need.

**Alerts.** Renaming a group from the second monitor opened the rename sheet on the first, because
`NSAlert` centres itself on the main display. Setting the frame beforehand does not survive:
`runModal()` re-centres as it starts. The move has to happen *inside* the modal loop — a block
queued for `.modalPanel` runs once the alert is up — and it goes to the screen the pointer is on,
which is the screen the click came from.

## D103. Grouping is a place inside a row, not a pause on top of one.

Hand-testing M13's grouping found it "shaky and nearly impossible", and the reason was that three
mechanisms were fighting over the same gesture.

`dragMoved(over:)` knew *which* row the drag was on and nothing about where in it, so every
`draggingUpdated` reordered the preview to put the dragged row at the target's index. That moved the
rows under a pointer that had not moved, which put a different row under it, which restarted the
600 ms dwell timer that was the only way to ask for a group. The dwell rarely elapsed; when it did,
it reset the preview to the stored order, so the bar visibly jumped back mid-drag.

The fix is to make position the input. `CatcherView` now reports where in the row the drag is,
normalised 0…1 from the row's top-left corner, and the model reads it along the bar's own axis. The
middle 40 % of a row that can take the dragged application means **group**; either end means
**insert here**, before or after depending on which end. 0.3…0.7 because a narrower band is a target
you have to stop moving to hit, and a wider one leaves no room to reorder — and the band only exists
at all on a row `canGroup` accepts, so a folder or a full group reorders across its whole length.

Three consequences, each of which was its own report:

- **Nothing moves while a group is being offered.** The preview is left exactly as it stands and the
  target grows a ring. The dragged row is no longer hidden from the rows while it hovers either:
  vanishing it shifted every row after it by one pitch, which is the same "different row under a
  still pointer" problem in a different coat.
- **The same intent is never acted on twice.** A `(target, zone)` pair that has just been applied is
  ignored until one of the two changes. Without it, the fresh coordinates that arrive after every
  preview change read as a new decision.
- **Two running applications can group.** `canGroup` used to require the target to be in the dock,
  so two loose icons could never become a folder — the one place everybody has learned to expect it.
  A running target is pinned on the way, in the same write as the group.

And the drop itself: a drag only committed if it landed exactly on a row's catcher. Let go in the gap
between two rows, on the section padding, or past the last row and the operation came back empty,
which reverted the whole drag — reported as "reordering a group silently reverts". The bar's own
hosting view now registers the row pasteboard type, so anywhere inside the bar is a drop that commits
the preview, and the rows' catchers still take the drops that land on a row because they sit deeper
in the hierarchy. Outside the bar is still a cancel, which is the only thing dragging a row off the
bar has ever meant.

## D104. The group popover takes the keyboard to be typed into, and only then.

Renaming a group used to be an `NSAlert` (D102) because the popover can never become key, and a text
field nobody can type into is worse than a menu item. But the popover shows a folder's title exactly
where iOS shows an editable one, so that is where people click — and an alert opening from it reads
as the wrong answer to a click they have made a thousand times elsewhere.

So the panel becomes key, on the same terms the bar's keyboard mode does (D99): **because the user
asked**, by clicking the name, and it hands the keyboard straight back to whoever had it the moment
the field closes. `acceptsKeyboardFocus` is the whole mechanism, it is set for the duration of the
edit and nothing else sets it, and the no-focus-theft guarantee (D3) is untouched for every other
click into the bar or the popover.

Three details the implementation turns on:

- **The field focuses itself.** The panel is made key in the same turn the SwiftUI branch holding the
  field appears, so focusing it from outside finds nothing there yet. It takes first responder in
  `viewDidMoveToWindow` instead, and selects what is in it.
- **No row catcher over the field.** `nexusRow` overlays an `NSView`, which would swallow the click
  that places the cursor. The title is a row *or* a field, never both.
- **Clicking away commits.** Escape cancels, Return commits, and anything that takes the popover
  away — a click outside, the pointer wandering off, the group being edited from elsewhere — commits
  what was typed. A name typed and left alone is a name that was meant.

The alert stays where it still fits: the row's own context menu, which has nowhere to put a field.
