# Decisions — Windows

The Accessibility window layer: counts, titles, flyouts, thumbnails, reserved space, minimized windows.

Part of the decision log; the index, and the rule these follow, are in
[`../decisions.md`](../decisions.md). Numbers are global and never reused, so the gaps
here are entries that live in another file, and the date each was made is in `git log`.

## D5. Window counts come from `CGWindowListCopyWindowInfo`, titles from the AX API.
Counts need no permission, titles do. Splitting the sources is what keeps Milestone 3
permission-free (§111.2).

## D18. Window counts are recomputed on every `NSWorkspace` application event and whenever the
pointer enters the sidebar.
macOS publishes no notification for another application opening a
window, and Milestone 3 must require zero permissions. Pointer entry is a user event, not a
timer, so the no-polling rule holds. Live per-window tracking arrives with the `AXObserver`s at
Milestone 4. Rejected: a refresh timer.

## D21. The window flyout opens on click or from the context menu, not on hover dwell.
`behavior.clickBehavior = .showWindowList` makes a click open it, and "Show Windows" is always in
a running application's context menu. A hover-dwell trigger would pop a panel open every time the
pointer crossed the sidebar on its way somewhere else. `ROADMAP.md` says "hover or click";
this ships the click half and leaves hover unbuilt.

## D22. `AXObserver` callbacks publish one coalesced `.windowsChanged(app)` per application
instead of per-window created/closed/retitled/focused events.
AX elements are not `Sendable`
and cannot cross into the event, and consumers re-read authoritative state on wake anyway
(D12) — so the finer-grained events would have carried no extra information. Bursts are
coalesced over 80 ms, which matters because `kAXTitleChangedNotification` fires on every
keystroke in an editor. `NexusEvent.windowCreated/windowClosed/windowTitleChanged/windowFocused`
were removed rather than left unpublished.

## D24. The flyout's whole content is gated on `target != nil`.
`NSHostingView` evaluates its body when it is constructed, not when its panel is ordered front,
so the permission screen's `.task` started the 1 Hz poll at launch and never stopped. Gating on
visibility is what actually enforces D13's "scoped to a visible screen". Measured: 0.00 s of CPU
over 45 s idle after the fix.

## D25. Only `AXStandardWindow` subroles appear in window lists.
Sheets, popovers, palettes and toolbars are AX windows too; listing them would make the flyout
noise. Windows without an `_AXUIElementGetWindow` id still list and activate under a synthetic
identifier — only their preview is lost (design/mvp.md §3.1).

## D36. The sidebar gets VoiceOver navigation, not arrow-key navigation.
`ROADMAP.md` Milestone 7 asks for "full keyboard navigation of the sidebar", but the sidebar
panel can never become key (D3) — that is the guarantee the whole product rests on. VoiceOver
drives it through the accessibility element tree, which needs no key status, and every row
carries a label, a value ("running, 3 windows") and a hint. Keyboard-driven work goes through
the search palette, which is the keyboard surface, exactly as `design/mvp.md` §2.1 anticipated.

## D37. Accessibility revocation is detected on the next AX call, not by polling.
`WindowService` re-checks `AXIsProcessTrusted()` on every entry point and publishes
`.permissionChanged(.accessibility, .denied)` on the transition, clearing its caches. The flyout
then reloads, which empties the stale window list and shows the explain-and-grant screen. No
timer was added: the only moment a stale window list can mislead the user is when they ask for
one.

## D60. The window list lives in the context menu; the flyout becomes "Show All Windows".
Reaching an application's second window took right-click → Show Windows → flyout, where the Dock
takes one step. The menu now opens with the windows, frontmost ticked. `NSMenu` is built
synchronously and AX calls are not, so the titles come from a cache warmed when the pointer enters
the row; a row with nothing cached shows no window section rather than blocking. Without
Accessibility there is no section at all, which is the same split as D5 — counts are
permission-free, titles are not.

## D61. Window-count badges come from the Accessibility list, and are hidden without it.
`CGWindowListCopyWindowInfo` is permission-free but counts the wrong things: measured here, Brave
showed 2 because its 387×64 "Find in page" bar is an ordinary layer-0 window, and Finder showed 2
where the menu listed 3. A badge that disagrees with the menu it sits next to is worse than no
badge, so counts now come from the same AX sweep that fills the menu — refreshed on the events
that already refresh counts, never on a timer — and the badge is not drawn at all while
Accessibility is missing. `WindowCounts.byProcess()` stays as the fallback that feeds nothing
visible; it is still what runs before the grant arrives.

## D62. A window with no AX subrole is not a window.
The subrole filter accepted elements that answered nothing at all, which is exactly what Finder's
desktop is — hence "Finder" appearing as a third window in its own menu. The filter now requires
`AXStandardWindow`, which also keeps out `AXUnknown` panels like a browser's find bar.

## D64. Hover opens the flyout after a delay; switching rows while one is open is instant.
Without the delay, sweeping the length of the bar opens and closes a dozen flyouts. Paying it
again for every row once one is already open is what makes hover docks feel sticky, so the timer
applies to opening, not to switching. The timer is cancelled the moment the pointer leaves the
row, and the flyout's existing 400 ms grace period is what lets the pointer travel from the row
to the flyout without it vanishing on the way.

## D65. A thumbnail arriving has to re-measure the flyout.
Previews are captured after the flyout is already on screen, and the panel's frame is computed
from the hosting view's fitting size at the moment it opens. Storing an image therefore grew the
content inside a panel that kept its old frame: the thumbnails were captured, cached and drawn
entirely outside the visible bounds. `requestPreview` now calls `onContentChange` on arrival.
Found live — the logs said `Preview for window 3246: image` while the flyout showed titles only.

## D66. The preview service's failure paths log at `.notice`, not `.debug`.
Same lesson as D48, in the one place it had survived: `os.Logger.debug` is memory-only, so "no
capturable window" and "preview unavailable" were invisible in exactly the situation they exist
for. The "window not found in `SCShareableContent`" branch had no logging at all.

## D70. Screen space is not reserved, windows are moved out of it.
`NSScreen.visibleFrame` is the menu bar's and the Dock's to shrink; macOS offers no public API,
and no entitlement, that lets a third party reserve space. The private `CGSSetWorkspaceDockRect`
route would mean shipping against an unversioned SPI to fight the component Nexus has already
asked to hide. So Reserved Space watches for windows that overlap the bar and moves them off it,
through the Accessibility permission the window list already needs — pushed if they still fit,
resized only if they do not. The ceiling is honest and visible: a window can *open* over the bar
and be nudged a moment later, where the Dock's space was never available in the first place.

Two rules keep it from becoming a nuisance. Auto-hide turns it off entirely — a bar that comes and
goes cannot own space, and moving windows aside every time it appeared without ever putting them
back would be worse than doing nothing. And an application that puts its window straight back wins
after four attempts inside two seconds: the alternative is a fight that neither side ends.

Everything is compared in Accessibility coordinates, which grow downwards from the primary
display's top-left, unlike Cocoa's. `ScreenGeometry.flipped` is the only place that knows.

## D88. Every row carries its own accessibility action.
The Definition of Done (§33) asks that Nexus be usable with the keyboard and by VoiceOver. The
labels were there from the start — every row has a label, a value carrying its state, and a hint —
and reading the bar worked. Pressing anything in it did not.

The cause is the same one that shapes half of Nexus: these panels can never become key, so nothing
in them is a SwiftUI `Button`. Rows are hit by `PanelRowInteraction` claiming the AppKit mouse-down,
and `.accessibilityAddTraits(.isButton)` only *says* button — it adds no action, so `AXPress` from
VoiceOver found nothing to perform and returned success having done nothing. Verified by pressing
the start-menu row through the Accessibility API: `AXPress` reported success and no menu opened.

So each row now adds `.accessibilityAction` next to its traits, doing exactly what its click does.
It has to live at the call site: an action added inside the `nexusRow` modifier is discarded by the
`.accessibilityElement(children: .ignore)` that every row applies outside it — which was tried
first, and measured, before writing twelve lines instead of one.

Two smaller things the same pass turned up: the panels had no `title`, so VoiceOver announced an
unnamed window for the bar, the palette, the flyouts and the start menu; and a single-window
application read as "running, 1 windows".

## D97. Three minimized windows, in the tail, in an order Nexus keeps itself.
macOS parks minimized windows at the end of its Dock. Nexus had nowhere for them: minimising a
window dropped its application's count by one and left the window reachable only by hovering that
application and reading the flyout.

*In the tail, not the scrolling middle.* A minimized window that scrolled away would be exactly as
lost as it was before, and the tail is the part of the bar that exists so Trash and Search never
scroll (M14). It costs `min(count, 3)` slots out of the application budget and gives every one back
when the last window is restored, the same arithmetic the now-playing row already uses.

*Three.* The tail is subtracted from the applications before they are laid out, so an unbounded
tail is a bar that shrinks every time somebody minimises something. Three covers the windows you
just put down; the older ones stay where they already were, in their application's flyout. A
scrolling minimized section was the alternative and it is a worse trade: a fourth budget in the zone
maths, for rows nobody looks at.

*Order kept here.* `AXMinimized` is a boolean and enumeration order is whatever an application's
window list happens to be, so "newest first" has to be remembered rather than read: a window that is
newly minimized goes to the front, and one that is restored, closed or whose application quit leaves
the list. Without that the rows would reshuffle every time any application's windows changed.

*No thumbnail.* A preview needs Screen Recording (M10). A tile that is blank without a permission is
worse than one that is honestly an application icon, and the flyout still shows thumbnails to
anybody who granted it.
