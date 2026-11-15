# Documentation

| | |
|---|---|
| [`decisions.md`](decisions.md) | The index of every ambiguity call: what was decided, why, and what was rejected. One entry per call, numbered `D1`, `D2`, … and referenced from the code by number. The entries themselves are in [`decisions/`](decisions/), six files by area, with the numbers global across them. |
| [`design/`](design) | How each piece works. One file per feature. |
| [`../ROADMAP.md`](../ROADMAP.md) | What was built, by milestone, and what is deliberately not built. Schedule, not design. |
| [`../ARCHITECTURE.md`](../ARCHITECTURE.md) | The shape of the codebase: targets, layers, what may depend on what. |
| [`../FEATURES.md`](../FEATURES.md) | The feature list with its permission for each, as a table. |
| [`verification.md`](verification.md) | What has been checked against a running, installed Nexus, and what has not — including the Definition of Done walkthrough. A dated log. |
| [`release-checklist.md`](release-checklist.md) | The manual walkthrough to run on an installed build before a release. The current list of what needs a human. |
| [`archive/plans/`](archive/plans) | Dated implementation plans that have been executed and merged. History only: nothing in them is pending, and the code is the source of truth. |
| [`reviews/`](reviews) | Dated reviews of the whole project and what came of them. |
| [`images/`](images) | Screenshots used by the README. |
| [`../Nexus_Project_Foundation_MVP.md`](../Nexus_Project_Foundation_MVP.md) | The original brief. "Foundation §n" in the other documents means a section of it. Sections 36–110 are a vision that is deliberately not built. |

## Where a new document goes

**A feature gets a file in `design/`** — named after the feature, not the milestone that shipped
it. Milestone numbers age; "dock replacement" does not. Cover what is specific to that feature and
link to `design/mvp.md` for the rules it inherits.

**A rule that applies to every feature goes in [`design/mvp.md`](design/mvp.md)**, which is the
cross-cutting document: panels and focus, permissions, layout vocabulary, display handling,
logging, what is tested and how. Split a separate `conventions.md` out of it the first time a
second feature document needs to restate one of its rules — not before.

**A one-off call goes in [`decisions/`](decisions)** — the area file it belongs to, with the next
free number and a row in the [`decisions.md`](decisions.md) index — even if it also appears in a
design document. The decision log is the place to look up *why*, and code comments cite it by
number.

Milestone scopes live in `../ROADMAP.md`; a dated plan for an implementer goes in `plans/` while it is being worked and moves to `archive/plans/` once merged. A design document describes the thing as it is meant to
work; it is not a schedule and does not need updating when a milestone slips.
