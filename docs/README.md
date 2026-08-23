# Documentation

| | |
|---|---|
| [`decisions.md`](decisions.md) | The index of every ambiguity call: what was decided, why, and what was rejected. One entry per call, numbered `D1`, `D2`, … and referenced from the code by number. The entries themselves are in [`decisions/`](decisions/), six files by area, with the numbers global across them. |
| [`design/`](design) | How each piece works. One file per feature. |
| [`../ROADMAP.md`](../ROADMAP.md) | What is built and what is next, by milestone. Schedule, not design. |
| [`../ARCHITECTURE.md`](../ARCHITECTURE.md) | The shape of the codebase: targets, layers, what may depend on what. |
| [`../FEATURES.md`](../FEATURES.md) | The feature list with its permission for each, as a table. |
| [`verification.md`](verification.md) | What has been checked against a running, installed Nexus, and what has not — including the Definition of Done walkthrough. |

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

Milestone plans live in `../ROADMAP.md`. A design document describes the thing as it is meant to
work; it is not a schedule and does not need updating when a milestone slips.
