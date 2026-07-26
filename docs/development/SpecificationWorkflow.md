<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Specification Workflow

**Status:** v1 — established during the PTIMER-225 baseline migration.
This is a working contract, not a finished process document. It will be
revised after real feature work (starting with PTIMER-221) has exercised it,
to reflect what actually worked rather than what was planned.

This document describes the *process* by which PTimer's living behavior
specifications are created, changed, and implemented. It does not itself
contain product behavior — product behavior lives in `docs/specs/**`.

---

## 1. Document layers

```
docs/requirements/Requirements.md
        ↓ (refines, does not duplicate)
docs/specs/**
        ↓ (informs)
engineering design / tasks
        ↓
implementation
        ↓
verification
```

- **`docs/requirements/Requirements.md`** is the higher-level, user-scenario
  and persona-oriented product requirements layer. It states user-visible
  needs and integrity invariants in prose, at the granularity of "the user
  can do X" or "the system shall never do Y."
- **`docs/specs/**`** is the detailed, testable behavior-contract layer,
  organized by product capability. Each file states individually-numbered,
  atomic requirements at a granularity a test or a code review can check
  directly.

**The two layers must not converge to the same level of detail.** A
capability spec requirement should be more specific than its corresponding
Requirements.md statement, not a restatement of it. For example:

```
Requirements.md:
  "The user can use multiple camera slots."

shooting/camera-slots.md:
  SLOT-001, SLOT-002, SLOT-SWITCH-001, ...
```

`docs/architecture/**` and `docs/development/**` sit outside this chain.
They describe *how the system is built* (module boundaries, ownership,
process) rather than *what the product does*. Architecture and process
material must never appear inside a `docs/specs/**` file's normative body.

## 2. What a living behavior specification is

A file under `docs/specs/**` describes **current, shipped product behavior**
for one product capability — **on `main`**. This is a branch-scoped
statement, not a path-scoped one: the same path means something different
depending on which branch it is read from.

- On `main`, `docs/specs/**` describes only what is actually implemented and
  shipping. Nothing proposed, planned, or partially built belongs there.
- On an open Spec PR branch (§10.1), the same path describes a **proposed**
  contract that is not yet implemented, and is expected to keep changing
  until it is approved. It is not a violation of "current-only" for a Spec
  PR branch to contain not-yet-shipped behavior — that is exactly what a
  Spec PR is for. It becomes a "current-only" violation only if it merges
  to `main` before the Code PR that implements it does (§10.5 forbids this
  merge order).

A file under `docs/specs/**` is otherwise:

- **Ticket-free.** No Jira ticket IDs, no PR references, no "as of PTIMER-NNN"
  framing in the normative body.
- **History-free.** No narration of how the behavior evolved, what was tried
  and rejected, or who decided what and when. A settled rejection that still
  carries real regression risk is compressed into a one-line entry under
  **Non-goals**, not a story.
- **The first artifact changed when a new requirement is proposed.** Per §1,
  it sits between Requirements.md and engineering design — a new capability
  or behavior change starts here, not in code.
- **Current-only.** A living spec describes what the product does today. It
  does not describe planned or anticipated future behavior, even when a
  future ticket is already known. (See §5, PTIMER-221 / My Filters as the
  concrete precedent.)

## 3. Capability ownership

`docs/specs/` is organized by product capability, not by ticket, delivery
order, or implementation layer:

```
docs/specs/
├── README.md
├── calculator/
│   ├── exposure.md
│   ├── nd-filters.md
│   └── target-shutter.md
├── shooting/
│   ├── camera-slots.md
│   └── reset.md
├── reciprocity/
│   ├── calculation.md
│   ├── catalog.md
│   ├── custom-profiles.md
│   └── details-and-guidance.md
├── timers/
│   ├── lifecycle.md
│   ├── workspace.md
│   └── alerts.md
└── cross-cutting/
    ├── persistence.md
    ├── localization.md
    └── presentation.md
```

A new independent capability gets a new file in the appropriate directory
(e.g. `calculator/my-filters.md`). The tree is not grown speculatively on
`main`: on `main`, a capability file exists only once its capability has
actually shipped, not in anticipation. On an open Spec PR branch (§10.1),
creating that new file *is* the proposal — a Spec PR for a brand-new
capability is expected to add the not-yet-implemented file, exactly as §2
already allows for existing files. It only becomes a "current-only"
violation if it merges to `main` ahead of the Code PR that implements it
(§10.5 forbids that merge order).

**Cross-capability inheritance.** When a new capability extends or shares
mechanics already owned by another file, it must not duplicate those
mechanics. It states its own capability-specific contract and references the
owning file by name for the shared part, e.g.:

> `<new-capability>` stacks are governed by the common stack behavior
> defined in `<owning-file>.md`. This document does not redefine those
> rules.

This pattern is illustrative only. Whether any specific future capability
(for example My Filters/PTIMER-221) actually shares an existing file's
contract this way, or needs its own independent one, is not decided by this
document — that is a product/behavior question, decided in that feature's
own Spec PR once its requirements are confirmed (see §5).

A shared invariant is defined in exactly one file. If a later feature's
requirements make an existing file's contract need to generalize (for
example, a stack contract written specifically for one input source needing
to become source-agnostic), that generalization happens in the Spec PR of
the feature that needs it — never speculatively during an unrelated baseline
or migration pass.

**Architecture is out of scope.** Module boundaries, state-ownership
diagrams, and platform-specific implementation structure belong in
`docs/architecture/**`, not `docs/specs/**`. A capability file may state a
*behavior difference* between platforms when one genuinely exists (e.g. a
platform-specific accessibility mechanism), but never *how* either platform
is internally structured to achieve it.

## 4. Requirement ID conventions

- **Format:** `<PREFIX>-<NNN>`, e.g. `ND-001`, `SLOT-SWITCH-001`,
  `RECIP-CALC-001`, `PERSIST-001`.
- **Never use the `FR-` prefix in `docs/specs/**`.** `FR-` (and `NFR-`)
  belong to `Requirements.md`'s own numbering (`FR-1.2a`, `NFR-D.1`, ...).
  Reusing it here would collide two different-altitude ID namespaces.
- **Prefer semantic segmented prefixes over numeric ranges.** `ND-STACK-001`,
  `ND-CLEANUP-001`, `ND-INTERACT-001` read correctly years later without a
  lookup table. A numeric range convention (`ND-100`–`ND-199` = stack, etc.)
  does not — the number alone carries no meaning, so it fails exactly the
  problem stable IDs are meant to solve.
- **Namespace table only where it earns its keep.** A file that uses several
  semantic prefixes whose scope is not immediately obvious from the prefix
  name alone should open with a short table:

  ```
  | Prefix | Owns |
  | --- | --- |
  | ND | Core ND values and notation |
  | ND-STACK | Shared stack behavior |
  | ND-CLEANUP | Zero-entry cleanup |
  | ND-INTERACT | Interaction/commit behavior |
  ```

  A file with one or two self-evident prefixes (e.g. `RESET-001`,
  `RESET-A11Y-001`) does not need this table — adding one would just be
  another thing to keep in sync for no real gain in clarity.
- **IDs are stable and append-only.** A retired ID is never reassigned to
  unrelated behavior. If a requirement is removed, mark it `RETIRED` with a
  one-line reason rather than deleting the ID silently, if it is plausible
  that a test, code comment, or PR still references it.
- **Not every sentence needs an ID.** Only normative, individually testable
  requirements get one. Purpose statements, contextual prose, and
  explanatory asides stay unnumbered.

## 5. Current baseline discipline

The baseline established by this migration describes **only currently
shipped behavior**, verified against the truth hierarchy in §6. Concretely:

- The ND filter stack (`calculator/nd-filters.md`) describes the shipping
  stack over the standard ND ladder only. It is not generalized in
  anticipation of PTIMER-221 (My Filters). That generalization, if the
  verified requirements of PTIMER-221 turn out to need it, happens inside
  PTIMER-221's own Spec PR.
- No capability file for a feature that has not shipped is created during a
  baseline or reconciliation pass.
- Historical material (see §6) is a candidate source of *evidence* about
  current behavior, never a source of *future* behavior.

## 6. Truth hierarchy

Every conflict between historical, current, and source-level material must
be resolved using this ordering, highest authority first:

1. **An explicit current product decision approved by the user.**
2. **Approved current product requirements / behavior specifications**
   (`docs/requirements/Requirements.md`, current `docs/specs/**`).
3. **Current source implementation and tests.**
4. **Historical task specs, Jira/Confluence records, reports, and prior
   agent reconstructions** (including the historical SDD reconstruction
   produced before this migration).

**Current source code is evidence, not automatically product truth.** If an
approved specification and the current implementation disagree:

```
approved spec == current source        → verified candidate
approved spec != current source        → conflict/ambiguity — do not silently
                                          pick source; the implementation may
                                          contain a regression
historical material != current spec    → historical material is a stale
                                          candidate for rejection, not an
                                          automatic override
source-only, no approved contract       → source is evidence; it is not
                                          promoted to product truth merely
                                          because it is what runs today
```

Historical material is never promoted into a living spec merely because it
describes what shipped at some point in the past, and never because it is
more detailed than the current approved spec. Detail is not the same as
correctness — a stale historical requirement can be extremely precise and
still describe behavior the product no longer has.

### Reconciliation classification

For every historical candidate requirement considered for migration:

```
candidate
    ↓ apply truth hierarchy
VALID        — current accepted behavior supports it; migrate with a new
               capability-scoped ID.
STALE        — superseded by a higher-authority current decision or spec;
               do not migrate; leave in the historical archive only.
AMBIGUOUS /
CONFLICT     — approved spec and source disagree, two approved documents
               disagree, or acceptance cannot be established from available
               evidence. Do not resolve unilaterally. Collect for a decision
               report (§8) and continue with unaffected capabilities.
```

**How confident the evidence is does not change this.** The AMBIGUOUS/
CONFLICT classification is not a fallback for genuinely unclear cases only —
it also applies when the agent doing reconciliation is highly confident
about which side is correct. Reading current source and concluding "the
spec is obviously the stale one here" does not authorize rewriting the spec
in the same pass; it authorizes writing up the conflict, with the
supporting evidence, for the decision report. Two documents at the *same*
truth-hierarchy level (for example, `Requirements.md` and a current
`docs/specs/**` file both being "approved current") that disagree with each
other are a CONFLICT by definition — there is no default tiebreaker between
peers, including "the more detailed one wins" (see §14).

## 7. Product research references

A capability file's optional **Product research references** section may
cite a source only when it is a *durable* source of current product intent
— something that still materially explains why the contract has its current
shape. The test is **continued relevance to current product intent**, not
where the material happens to live (a Confluence wiki page is not
automatically durable; some wiki pages are themselves marked historical or
superseded).

May remain:
- Product/photography/exposure research that explains a current scope
  decision.
- Manufacturer or source-data research behind a current reciprocity policy.

Must be excluded:
- Jira implementation tickets, PR references, implementation reports.
- Superseded design drafts and historical decision chronology.
- Any source explicitly marked obsolete/superseded in its own citation text.
- A source that no longer supports any current product behavior.

## 8. Handling product ambiguities

An agent performing reconciliation or migration work must never silently
resolve a genuine product ambiguity — by picking an interpretation, by
rewriting behavior to make documents internally convenient, or by treating
current source code as automatically authoritative over an approved spec.

When an ambiguity is found, it is collected in this form:

```
ID / capability:
Conflict:
Higher-authority evidence:
Current implementation evidence:
Historical evidence:
Why a product decision is required:
Options:
Your recommendation:
```

Only genuine product ambiguities are escalated this way. Implementation
detail, wording choices, and document-organization questions that an agent
can resolve within the rules in this document are not escalated.

## 9. Roles and approval responsibility

- **The user** is the final product decision authority. Any item classified
  as a genuine ambiguity is decided by the user, never inferred.
- **ChatGPT** reviews and classifies spec feedback (§10) — questions,
  objections, and conflicts raised during implementation — and escalates
  only the ones that are genuine product decisions to the user.
- **Claude / Codex**, acting as implementer, may raise spec feedback (§10)
  but does not resolve a product-impacting question on its own. It is
  expected to keep working on unaffected parts of a task rather than
  stalling entirely on one open question.

## 10. Spec PR / Code PR model

A feature or behavior change is normally represented by two pull requests
against the application repository, both branched from `main`:

```
main
 ├── spec/<ticket>-...
 │      └── Spec PR — docs/specs/** documentation only
 │
 └── feature/<ticket>-...
        └── Code PR — implementation and tests
```

Both branches normally branch from `main` directly. A Code PR is not
stacked on top of its Spec branch by default — implementation consumes an
explicit, recorded revision of the Spec PR (see §10.3), not an in-progress
branch tip that might still move.

### 10.1 Spec PR

- Touches `docs/specs/**` only (and, rarely, a clarifying note in
  `docs/requirements/Requirements.md` — see §1).
- Is opened as a **Draft PR** and stays draft while product behavior is
  still being decided. It describes a **proposed** product contract that is
  not yet implemented.
- Is revised in place as product decisions change. A change of mind does
  not produce a new PR; the same Spec PR is updated until the contract is
  approved.
- Passes through two distinct approval points, not one (see §10.4):
  **initial approval** (the user and ChatGPT agree the drafted contract is
  what should ship — this is what unlocks starting a Code PR) and **final
  conformance confirmation** (after implementation, confirming the Code PR
  satisfies the Spec PR's latest revision and any spec feedback raised
  during implementation has been resolved — this is what unlocks merge).
  A Spec PR can be initially approved, then revised again mid-implementation
  if a `[SPEC-CONFLICT]` or `[SPEC-QUESTION]` (§12) surfaces a real gap;
  each revision re-opens final conformance confirmation, not initial
  approval.

### 10.2 Code PR

- Touches implementation and tests. It must not also modify
  `docs/specs/**` — a behavior change discovered during implementation goes
  back to the Spec PR, not into the Code PR directly.
- States which Spec PR it implements and against which revision (commit SHA)
  of that Spec PR (see the checklist in §11).
- Is reviewed, tested, and (for user-visible behavior) verified on-device
  against the Spec PR's latest approved revision before merge.

### 10.3 Recording the Spec revision an implementation consumes

Because a Spec PR can be revised after implementation starts, the Code PR
must record the exact Spec PR revision (a commit SHA on the Spec branch) it
was built against, and confirm that revision matches what was actually
implemented before requesting final review. If the Spec PR moves after
implementation started, the Code PR is checked against the new revision —
either the implementation already satisfies it, or the Code PR is updated
and the check is repeated.

### 10.4 Lifecycle states

A Spec PR moves through:

1. **Proposed** — product behavior is being drafted/discussed. No approval
   yet; a Code PR must not start from this state.
2. **Initially approved, awaiting implementation** — the user and ChatGPT
   agree the drafted contract is what should ship. This unlocks starting a
   Code PR against this revision. It does not yet mean implementation
   matches it — nothing has been built against it yet.
3. **Implementation in progress** — a Code PR exists and records which
   Spec PR revision it targets (§10.3). If implementation surfaces a
   `[SPEC-QUESTION]`/`[SPEC-OBJECTION]`/`[SPEC-CONFLICT]` that changes the
   contract, the Spec PR is revised and returns to state 2 for the changed
   part; unaffected parts do not need to be re-approved.
4. **Final conformance confirmed** — the Code PR implements the Spec PR's
   latest revision, verification passes, and any spec feedback raised
   during implementation has been resolved. This — not state 2 — is the
   gate for merge.
5. **Merged** — Spec PR and Code PR merge in the agreed sequence (§10.5).

### 10.5 Merge sequence

Merge only when: the product spec reached final conformance confirmation
(state 4 above) for everything the Code PR implements, automated
verification passes, user-device verification (where applicable) passes,
and both PRs are merge-ready.

Then, in this order: **the Code PR merges first, the Spec PR merges
immediately after.** This order is not arbitrary — §2 requires that
`main`'s `docs/specs/**` describe only implemented behavior, and merging
the Spec PR first would put unimplemented behavior on `main`, even if only
for the short window until the Code PR follows. Merging the Code PR first
briefly leaves shipped behavior undocumented instead, which is the lesser
and shorter-lived gap, closed by the very next merge. The originating
ticket closes only after both have merged, once the actual product and the
living spec agree.

## 11. PR checklist (candidate, no CI enforcement yet)

These are lightweight, human-reviewed checklist items, not automated gates.
CI enforcement is deliberately deferred until this process has been
exercised on real feature work and a repeated, concrete failure mode
justifies automating a specific check — see §13.

**Spec PR:**
- [ ] This PR changes product-spec/workflow documentation only.
- [ ] Any unresolved product ambiguities are identified in the PR
      description, not silently resolved.
- [ ] The PR does not mix in implementation changes.

**Code PR:**
- [ ] States the Spec PR it implements.
- [ ] States the exact Spec PR revision (commit SHA) implemented against.
- [ ] States that the implementation was reviewed against that revision.

## 12. Spec feedback protocol

An implementer (Claude or Codex) or reviewer who finds a problem with a
Spec PR's product contract — rather than with its own implementation —
raises it as a comment using one of these markers, never by silently
reinterpreting the spec or silently implementing something else instead:

- **`[SPEC-QUESTION]`** — the specification is insufficient to determine
  behavior; a case exists that the spec does not decide.
- **`[SPEC-OBJECTION]`** — the reviewer believes the requirement itself is
  problematic, unimplementable as written, or internally inconsistent.
- **`[SPEC-CONFLICT]`** — the reviewer found a conflict between this
  requirement and another requirement, an accepted product contract, or
  verified current behavior.

Each comment should include, where applicable:

```
Requirement:
Issue:
Evidence:
Implementation impact:
Suggested interpretation:   (optional)
```

Product-impacting feedback is never resolved silently by the implementing
agent. ChatGPT reviews and classifies these comments and escalates only
genuine product decisions to the user (§9).

## 13. What this document does not claim

This workflow describes an intended process, not an automated one. In
particular:

- There is no CI enforcement of the path separation between Spec PRs and
  Code PRs, and no automated check that a Code PR's stated Spec revision is
  accurate. These are currently human-reviewed conventions.
- There is no tooling that detects ID collisions, retired-ID reuse, or
  drift between a capability file and the source it describes. Consistency
  is maintained by review discipline during migration and subsequent PRs.

If a specific failure mode recurs in practice, add the minimal check that
would have caught it (e.g. a path-filtered CI job, a PR template field)
rather than a general automation framework. This document should be updated
at that point to describe what was actually added.

## 14. Lessons from the PTIMER-225 baseline migration

Observations from actually applying §6–§8 across the full capability tree,
recorded here so the next migration or reconciliation pass does not have to
rediscover them:

- **Confidence is not an exception to escalation, even for the person doing
  the reconciling.** A first pass at this migration found a case where
  current source code visibly disagreed with a previously-approved spec
  (a UI behavior description matching a pre-fix version of the code) and
  resolved it by rewriting the spec to match source, in the same pass that
  found it. That was a truth-hierarchy violation — "approved spec !=
  source" is a CONFLICT requiring a decision regardless of how confident
  the evidence looks, not an invitation to silently prefer source. It was
  reverted to an inline-flagged, unresolved conflict (see the PTIMER-225
  decision report, item A). The lesson generalizes: being sure you know
  the answer is not one of the listed classifications.
- **"More detailed" is not a tiebreaker, including between two approved
  documents.** A historical reconstruction's specific numbers (e.g. exactly
  which films receive a given treatment) were stale simply because the
  product grew after the historical ticket was written — correctly
  resolved against the current spec there. But the same instinct ("the more
  specific/detailed source must be the current one") was then wrongly
  applied to resolve a disagreement between two *peer* approved documents
  (`Requirements.md` and `DomainSchema.md` disagreeing on whether custom
  table reciprocity profiles are shipped) in favor of the more detailed
  one. That is not a valid tiebreaker between peers — reverted to an
  inline-flagged conflict (decision report, item B). Detail should raise a
  question, not settle one, and this applies with extra force when both
  sides are at the same authority level.
- **App-shell behavior needed its own file, not a shrug.** Global
  presentation rules (fixed portrait orientation, one primary screen
  hosting both calculator and timers, layout density tiers) didn't belong
  to any single capability file without being misattributed to one. Rather
  than leaving them unowned, `cross-cutting/presentation.md` was added.
- **A bare citation is not a durable reference.** The "Product research
  references" section (§7) was left out of every file in this baseline: the
  only content available for most citations was a short title against a
  wiki page id, with no accessible page content to verify or usefully
  summarize. A bare id is not more useful in the new tree than it was in
  the old one. If a future editor has real access to the underlying
  research, adding a substantive (not just cited) reference section to the
  relevant file is more useful than restoring the old citation list as-is.
