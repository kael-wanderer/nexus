# Application groups

Milestone 13. Drag one application onto another to put both in a folder, the way iOS and Launchpad
do — for the applications that deserve a place in the bar but not a slot each.

This is the one of the three that changes the stored schema, which is why it goes last.

## Schema: the first migration

Today a pinned entry is a bundle identifier:

```swift
public var pinnedApplications: [String] = []
```

A group is not an application, so the list becomes a list of entries — the same list a folder
stack later joins as a third kind (`folder-stacks.md`), and groups stay groups *of applications*:
dropping something on a folder reorders it rather than grouping with it.

```swift
public enum DockEntry: Codable, Sendable, Equatable, Identifiable {
    case application(String)                 // bundle identifier
    case group(ApplicationGroup)
}

public struct ApplicationGroup: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String                  // auto-named, user-editable
    public var applications: [String]        // ≤ capacity
}
```

`NexusConfiguration.version` goes **1 → 2**, and the migration is the one the roadmap has been
promising since Milestone 6: read `pinnedApplications` as `[String]`, map each to
`.application(_)`, write `pinnedEntries`. The old key is kept, unread, for one release so a
downgrade does not lose the dock. This is the first exercise of the migration framework, and the
test that matters is a v1 file loading into v2 with the same dock, in the same order.

## Interaction

- **Create**: drop an application onto another application. Both leave their slots, a group takes
  the target's position — the drag preview (D59) already shows exactly this, since a group is one
  row like any other.
- **Capacity**: 9 (3×3) by default, 16 (4×4) as a setting. A drop onto a full group is refused
  visually — the row does not accept the drag — rather than silently dropped.
- **Open**: click opens a popover of the group's applications on a grid, positioned like the window
  flyout, with the same non-activating panel rules.
- **Name**: auto-generated at creation, editable in the popover's header. Removing the last
  application dissolves the group; removing the second-to-last leaves one application and
  dissolves it too, because a folder of one is a lie.
- **Drag out**: dragging an application from the popover back to the bar takes it out of the group.

## Auto-naming

Applications declare `LSApplicationCategoryType` in their `Info.plist`
(`public.app-category.social`, `.developer-tools`, …). The group takes the category shared by the
majority of its members, mapped to a display name — Slack + Telegram + WhatsApp becomes "Social",
Xcode + Terminal becomes "Developer". No agreement, or no categories at all, falls back to
"Group". `LaunchServices` supplies this for free from the bundle Nexus already reads for the icon.

## Row rendering

A group draws as a rounded tile holding the first four member icons on a 2×2 grid, which is what
both iOS and Launchpad do, and what makes a group readable at 40 pt. The running dot is drawn if
*any* member is running; the window-count badge is not drawn for groups at all — a number that
sums several applications answers a question nobody asked.

## Settings

`behavior.groupCapacity` ∈ {9, 16}, default 9. Grouping itself has no on/off switch: a dock with
no groups behaves exactly as it does today, which is the same thing an "off" switch would buy.
*(If you want the toggle anyway, it is one line — say so.)*

## Rules it inherits

- Drag mechanics, the live preview and the section-crossing rules from `dock-parity.md` (D59, D63).
- Popover panels never take focus (`design/mvp.md` §2.1).
- Configuration is clamped and tolerant on decode: a group with 40 members loads as its first 9,
  a member whose application has vanished is dropped, and a group left empty is dissolved on load.

## What shipped

The schema, the interaction and the naming as specified. Four things went differently:

- **Grouping needs a dwell, not just a drop.** Rows already move aside as a drag passes over them
  (D59), so "dropped on a row" and "dropped between rows" are the same gesture. Resting on a row
  for 600 ms is what switches meaning: the rows stop sliding, the target grows a ring, the dragged
  row leaves the bar, and letting go merges. Dragging past a row still only reorders.
- **Renaming is a menu item and an alert, not the popover's header.** The popover can never become
  key (`design/mvp.md` §2.1), so a text field in it is a text field nobody can type into.
- **Capacity is enforced by repair, not only at the drop.** `[DockEntry].repaired(capacity:)` runs
  on load and after every edit: it trims an over-full group, drops an application listed twice,
  turns a group of one into that application and deletes an empty one. One function, so a
  hand-edited `defaults` payload gets the same treatment as a drag.
- **The legacy key is written, not just kept.** `NexusConfiguration.encode` still emits
  `pinnedApplications` — the flattened dock — beside `pinnedEntries`, so a downgrade to a v1 build
  finds its dock rather than an empty bar. Nothing reads it.

Verified live: a v1 configuration on disk with three pinned applications loads as v2 with the same
three, in the same order, with the legacy key still present. The drag itself is covered by tests
rather than by a screenshot — the screen locked mid-session, and driving a 600 ms dwell with
synthetic events needs an unlocked one.

## Tests

- v1 → v2 migration: the same dock, the same order, groups absent.
- Create by drop, capacity refusal at 9 and at 16, dissolve at one member.
- Auto-naming picks the majority category and falls back to "Group".
- A vanished member, an over-full group and an empty group all survive a decode.
