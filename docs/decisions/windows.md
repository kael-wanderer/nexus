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

## D100. A minimized window stops calling itself a standard window.

The minimized section (M22) shipped with nothing in it, and the reason was two milestones older
than the feature. D25 keeps sheets, palettes and Finder's desktop out of the window list by
requiring `AXSubrole == AXStandardWindow`. Minimising a window **changes that subrole**: Finder's
window reads `AXDialog` the moment it goes to the Dock, so the filter dropped it and the
enumeration went from nine windows to eight instead of nine-with-one-minimized. Measured, not
guessed — System Events reports `minimized=true subrole=AXDialog` for exactly that window.

The rule is now: a standard window always counts, and anything currently minimized counts unless it
is `AXUnknown`. `AXUnknown` stays excluded because that is what a find bar or a toolbar overlay
reports, and one of those being minimized is not a window anybody wants back.

This was never only about M22: the window flyout has claimed to list minimized windows since M4, and
it could not have.

## D112. The switcher shows one card per window, not per application.
`⌘Tab` already reaches every application and cannot reach a second window belonging to one — a
switcher that repeated it would be a worse `⌘Tab`. Two Finder windows are two cards, and grouping
by application (§4) is a view drawn on top of that, never a collapse of it.

## D113. Bulk previews fetch `SCShareableContent` once and capture four at a time.
`WindowPreviewService.preview` fetches `SCShareableContent` per call, and that fetch is the
expensive part of a capture — a twelve-window grid asking for it twelve times made the grid
unusable rather than merely slow. The bulk entry point fetches it once and hands the captures to a
task group capped at four in flight, each result delivered as it lands rather than held for the
whole batch to finish. Four rather than all of them at once because the work is one compositor's
either way; the cache the hover flyout already keeps rose from 32 entries to 64 to hold a grid's
worth alongside it.

## D114. The switcher asks for Screen Recording; the hover flyout still does not.
`design/mvp.md` §3.5 says a missing permission degrades in silence, and every feature but this one
keeps to that. A missing thumbnail in a flyout is a garnish; a wall of identical application icons
is the switcher failing at the only job it has. The offer is the existing `PermissionRequestView`,
one row above the grid, dismissible and never shown again once dismissed or granted — the grid
below it stays fully usable, with icons, whether or not the offer is showing.

## D116. Escape clears the filter before it closes the panel.
What every macOS search field does. The switcher's filter needed the rule spelled out because a
mistyped filter here would otherwise cost the whole panel: clearing it first is what stops one
Escape from closing a panel the user only meant to empty a field in.

## D118. The window card's title moved onto the thumbnail as a chip.
The card used to be a thumbnail with a caption underneath (M10); the restyle reference draws the
title inside the card, over the bottom-leading corner of the image, and nothing sits below it any
more. `LabelChip` — white text on a dark rounded tile — is the piece both flyouts use for this, so
a card's title and the now-playing panel's track title are drawn the same way rather than two
near-identical one-off overlays. The trade is real: `WindowCard`'s caption used to wrap onto a
second line for a long title, and a chip truncates to one. Accepted, because the card is what a
"windows of this application" screenshot is judged against, and the caption's second line was never
the point of it.

## D119. Quit and New Window joined the flyout's header; New Window presses an AX menu item on
`WindowService`, and Quit sits behind a confirmation.
The header grew two buttons: Quit (`NSRunningApplication.terminate()`, the same request the Dock's
own "Quit" sends) and New Window. There is no API for "open a new window" — no AX action, no
`NSRunningApplication` method — so New Window instead walks the target's AX menu bar for the item
whose `kAXMenuItemCmdCharAttribute` is `n` and presses that, `AX.perform`, the same primitive
`WindowService.activate` and `.close` already press buttons with. Rejected: synthesizing a ⌘N
keystroke, which would go to whichever application is frontmost — not necessarily the flyout's
target, since the flyout takes no keyboard focus (D3) — and rejected matching by the item's title,
which is localized and varies ("New Window", "New Tab", "Nouvelle fenêtre"). An application that
does not map ⌘N to a new window does whatever it does map: the search finds nothing, and logs at
`.notice` rather than guessing at a substitute.

The walk shipped first as a synchronous method on the `@MainActor` view model, called straight from
the button — which meant an unresponsive application's AX round trip froze Nexus's whole UI, not
just the flyout, for as long as `AXBridge`'s own 0.25 s messaging timeout allowed it to run. A
whole-branch review caught it: `AXBridge.swift` says outright that every AX call blocks for as long
as the target takes to answer and that callers live on `WindowService`'s actor, never the main
thread, and the menu walk was the one caller that did not. Moved to `WindowService.newWindow(for:)`,
beside `activate` and `close`, with the same trust check, the same per-application unresponsive-set
bookkeeping, and the same `NexusError.timedOut` / `.permissionDenied` / `.targetDisappeared`
handling `windows(for:)` already has — the view model now reaches it through a `Task`, exactly the
way it already reaches `activate`. The same review found `AXBridge`'s menu walk was also missing
`AXUIElementSetMessagingTimeout` on the children it discovers — `windows(of:)` sets it on every
window it returns, deliberately, and the menu walk now matches: every menu-bar child the recursion
touches gets the same 0.25 s ceiling, or an application that answers slowly on one submenu but not
another could still block past it.

Quit, unlike New Window, got a `confirmationDialog` naming the application and giving the Quit
action the destructive role. The flyout opens on passive hover and the two buttons sit 26×26 pt
apart with only their SF Symbol to tell them apart (`macwindow.badge.plus` vs. `power`) — close
enough that a whole-branch review flagged a slip as one mis-click from terminating another
application, which `NSRunningApplication.terminate()` does not undo. The bar's own Quit
(`SidebarView`'s context menu) already asks for two deliberate steps — right-click, then choose
Quit from the menu — before it fires; the flyout's button had none. New Window gets no such gate:
opening an unwanted window costs a keystroke to close and nothing else, which is not the kind of
mistake a confirmation earns its interruption for.

## D120. One `behavior.flyoutSize` setting sizes both hover panels.
Small / medium / large, default medium — medium being the reference screenshot's own measurements
for the window flyout's cards, the now-playing panel's artwork, and its transport tiles. One
setting rather than one per panel, because the two panels are one visual family after this restyle
(`FlyoutPanel.swift`) and a person resizing "the flyouts" should not have to find and match two
separate controls to keep them looking like they belong together. The per-size numbers live in one
table next to the views that read them, not in the configuration type itself — `NexusConfiguration`
knows the setting exists, not what a "medium" card measures.
